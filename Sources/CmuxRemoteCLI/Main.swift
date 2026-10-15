import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteMac
import CmuxRemoteClient

@main
struct Main {
    static func main() async {
        do { try await run() }
        catch { let text = (error as? BridgeError)?.message ?? "cmux-remote could not start. Check configuration and permissions."; FileHandle.standardError.write(Data((text + "\n").utf8)); exit(1) }
    }
    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst()); let command = args.first ?? "help"
        let options = CLIOptions(args: Array(args.dropFirst()))
        let home = FileManager.default.homeDirectoryForCurrentUser
        let state = BridgeState(directory: URL(fileURLWithPath: options.value("state") ?? home.appendingPathComponent(".local/state/cmux-remote").path))
        let port = Int(options.value("port") ?? "7740") ?? 7740
        var runtimeEnvironment = ProcessInfo.processInfo.environment
        if command == "resident" {
            if FileManager.default.fileExists(atPath: state.directory.appendingPathComponent("cmux-setup.json").path) {
                runtimeEnvironment.merge(try MacSetupRepository(directory: state.directory).environment()) { _, saved in saved }
            }
        }
        switch command {
        case "setup":
            let inherited = ProcessInfo.processInfo.environment
            let socket = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: inherited, home: home)
            _ = try await CLIControlClient(executable: URL(fileURLWithPath: "/Applications/cmux.app/Contents/Resources/bin/cmux"), socketPath: socket).request("system.ping", params: [:])
            var setup = inherited; setup["CMUX_SOCKET_PATH"] = socket
            try MacSetupRepository(directory: state.directory).save(environment: setup)
            print("cmux Remote is connected to local cmux. Open Remote Settings to continue.")
        case "discover", "connect": try await ConnectionCommand().run(command: command, options: options, state: state)
        case "mirror": try await MirrorCommand().run(options: options, state: state)
        case "init": try state.initialize(); print("Initialized private TLS and pairing state.")
        case "enrollment", "clients": try await OwnerCommand().run(family: command, options: options, state: state, port: port)
        case "pairing" where !options.contains("legacy"):
            var args = ["open"] + options.args
            if options.value("port") == nil { args += ["--port", String(port)] }
            try await OwnerCommand().run(family: "enrollment", options: CLIOptions(args: args), state: state, port: port)
        case "pairing":
            let pairing = try state.pairing(host: options.value("host") ?? LANAddressResolver().address() ?? "localhost", port: port)
            if options.value("format") == "json" {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(pairing), as: UTF8.self))
            } else {
                print("Scan this code in cmux remote on your iPhone. Keep it private.")
                print(try TerminalQRCode().render(PairingLinkCodec().encode(pairing)))
                print("Endpoint: https://\(pairing.host):\(pairing.port)")
            }
        case "serve", "resident":
            if (options.contains("pair") || command == "resident"), !FileManager.default.fileExists(atPath: state.directory.appendingPathComponent("token").path) { try state.initialize() }
            BridgeLog.shared.configure(directory: state.directory)
            BridgeLog.shared.info("bridge", "\(command) starting pid=\(ProcessInfo.processInfo.processIdentifier)")
            let machine = try BridgeMachineLease(home: home)
            let lease = try BridgeRunLease(directory: state.directory)
            defer { withExtendedLifetime((machine, lease)) {} }
            let mutations = MutationLedger(directory: state.directory)
            let cmux: any CmuxControlling
            let localDesktop: (any CmuxControlling)?
            let desktopSocket: String?
            let roots = [URL(fileURLWithPath: runtimeEnvironment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path), URL(fileURLWithPath: runtimeEnvironment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)]
            let transcripts = TuiTranscriptLocator(claudeRoot: roots[0], codexRoot: roots[1])
            let transcriptRoots: [URL]
            if options.contains("demo") {
                let directory = state.directory.appendingPathComponent("demo", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let transcript = directory.appendingPathComponent("conversation.jsonl")
                if !FileManager.default.fileExists(atPath: transcript.path) {
                    let sample = #"{"type":"assistant","uuid":"welcome","message":{"content":[{"type":"text","text":"Welcome to **cmux remote**. Pairing, history and sending are running through your local Bridge."}]}}"# + "\n"
                    try Data(sample.utf8).write(to: transcript)
                }
                let demo = DemoCmux(transcript: transcript.path, project: directory.path)
                cmux = demo; localDesktop = demo; desktopSocket = nil; transcriptRoots = [directory]
            } else {
                let sources = try await SourceBackends(options: options, environment: runtimeEnvironment, home: home, transcripts: transcripts, directory: state.directory, mutations: mutations)
                cmux = sources.controller; localDesktop = sources.desktop; desktopSocket = sources.desktopSocket; transcriptRoots = roots
            }
            let service = SessionService(cmux: cmux, home: home, transcriptRoots: transcriptRoots, mutations: mutations)
            let events: Task<Void, Never>?
            if let socket = desktopSocket {
                let client = CmuxEventClient(path: socket, password: runtimeEnvironment["CMUX_REMOTE_SOCKET_PASSWORD"], capability: runtimeEnvironment["CMUX_SOCKET_CAPABILITY"])
                let monitor = CmuxEventMonitor(repository: CmuxEventCursorRepository(directory: state.directory),
                    consume: { after, frame in try await client.consume(afterSequence: after, onFrame: frame) },
                    invalidate: { await service.invalidateEventBindings() }, refresh: { _ = try await service.sessions() },
                    accept: { await service.acceptEvent($0) })
                events = Task { await monitor.run() }
            } else { events = nil }
            defer { events?.cancel() }
            let authority = try state.authority(name: options.value("name") ?? Host.current().localizedName ?? "cmux Bridge")
            let mac: MacCompanionService?
            if let localDesktop {
                let discovery = ResidentMacDiscovery(discovery: await MainActor.run { BridgeDiscovery() }, excludingHostID: authority.host.id, enabled: !options.contains("no-discovery"))
                await discovery.start()
                let connections = MacConnectionRepository(directory: state.directory)
                let nativeGroup = NativeRemoteWorkspaceGroup(local: localDesktop)
                let executable = URL(fileURLWithPath: CommandLine.arguments[0])
                let mirrors = WorkspaceMirrorCoordinator(local: localDesktop, executable: executable, stateDirectory: state.directory, nativeGroup: nativeGroup,
                    checkpoints: MirrorCheckpointRepository(directory: state.directory))
                let authorize: @Sendable (String, String) async throws -> (HostIdentity, any MirrorRemoteControlling) = { host, workspace in
                    let connection = try await connections.connection(hostID: host)
                    guard connection.grant.value.scope.workspaces.contains(workspace.lowercased()), connection.grant.value.scope.capabilities.contains(.terminalRead) else {
                        throw BridgeError("scope_denied", "Approve this workspace for terminal viewing first.", status: 403)
                    }
                    return (connection.host, try RemoteMirrorClient(connection: connection))
                }
                _ = try await mirrors.restore(authorize: authorize)
                let catalog = NativeWorkspaceCatalog(local: localDesktop, repository: NativeWorkspaceRepository(directory: state.directory), mirrors: mirrors,
                    grouping: nativeGroup, executable: executable, stateDirectory: state.directory, authorize: authorize)
                let companion = MacCompanionService(repository: connections, mirrors: mirrors, discovery: discovery, catalog: catalog)
                mac = companion
            } else { mac = nil }
            let launcher = SessionLauncher(cmux: cmux, home: home, mutations: mutations, sessions: { try await service.sessions() })
            let router = BridgeRouter(service: service, authority: authority, legacyToken: options.contains("legacy") ? try state.token() : nil, mirrors: RemoteMirrorService(cmux: cmux, mutations: mutations), launcher: launcher)
            let relayRepository = RelayConfigurationRepository(directory: state.directory)
            if let origin = options.value("relay") {
                if origin == "off" { try relayRepository.remove() }
                else {
                    guard let path = options.value("relay-key-file") else { throw BridgeError("invalid_input", "Pass a private --relay-key-file with the relay origin.") }
                    _ = try relayRepository.save(origin: origin, keyFile: path)
                }
            }
            let relay: CloudRelayService?
            let relayKeyFile: String?
            if let configuration = try relayRepository.load() {
                try await authority.configureRelay(origin: configuration.origin)
                relayKeyFile = configuration.keyFile
                relay = try CloudRelayService(origin: configuration.origin, secret: relayRepository.secret(configuration), router: router, authority: authority)
            } else { relay = nil; relayKeyFile = nil }
            let sharing = ManagedSharingService(state: state, authority: authority, router: router,
                listen: options.value("listen") ?? (command == "resident" || options.contains("pair") ? "0.0.0.0" : "127.0.0.1"), port: port, advertise: !options.contains("no-discovery"), relay: relay, relayKeyFile: relayKeyFile,
                workspaces: { try await service.workspaces()["workspaces"].array?.compactMap { $0["id"].string } ?? [] },
                remembersChoice: command == "resident")
            let ready = AsyncThrowingStream<Void, any Error>.makeStream()
            let owner = Task {
                do { try await OwnerControlServer().run(path: state.directory.appendingPathComponent("owner.sock").path, authority: authority, service: service, mac: mac, sharing: sharing, onListening: { ready.continuation.yield(()); ready.continuation.finish() }) }
                catch { ready.continuation.finish(throwing: error); throw error }
            }
            defer { owner.cancel() }
            var iterator = ready.stream.makeAsyncIterator(); _ = try await iterator.next()
            await mac?.start()
            let qr: String?
            if options.contains("pair") {
                guard let host = options.value("host") ?? LANAddressResolver().address() ?? (relay != nil ? "localhost" : nil) else { throw BridgeError("lan_unavailable", "No private LAN address was found. Connect to Wi-Fi or pass --host.") }
                let workspaces = try await service.workspaces()["workspaces"].array?.compactMap { $0["id"].string } ?? []
                let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: host, port: port), workspaces: workspaces)
                qr = try TerminalQRCode().render(EnrollmentLinkCodec().encode(bootstrap))
            } else { qr = nil }
            if command == "serve" { _ = try await sharing.start() } else { await sharing.restore() }
            if let qr { print("Scan to request enrollment, then approve that exact device using enrollment pending/approve."); print(qr) }
            // Resident owner/discovery/mirror services stay alive while LAN sharing is off.
            try await owner.value
        case "doctor":
            let roots = TuiTranscriptLocator(claudeRoot: home.appendingPathComponent(".claude"), codexRoot: home.appendingPathComponent(".codex"))
            let sources = try await SourceBackends(options: options, environment: runtimeEnvironment, home: home, transcripts: roots, directory: nil, mutations: MutationLedger())
            _ = try await sources.controller.request("system.ping", params: [:]); print("Local cmux backends are reachable.")
        default:
            print("cmux-remote setup|resident|init|serve|pairing|enrollment|clients|discover|connect|mirror|doctor [--tui-socket PATH] [--relay HTTPS_ORIGIN|off] [--relay-key-file PATH] [--pair] [--legacy] [--no-discovery] [--state PATH] [--socket PATH] [--cli PATH] [--direct-socket] [--listen HOST] [--host HOST] [--port PORT] [--format json] [--demo]")
        }
    }
}
