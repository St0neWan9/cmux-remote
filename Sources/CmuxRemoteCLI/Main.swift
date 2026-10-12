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
            else if runtimeEnvironment["CMUX_SOCKET_CAPABILITY"] == nil { throw BridgeError("setup_required", "Connect this app to cmux first.") }
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
            let cmux: any CmuxControlling; let roots: [URL]
            if options.contains("demo") {
                let directory = state.directory.appendingPathComponent("demo", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let transcript = directory.appendingPathComponent("conversation.jsonl")
                if !FileManager.default.fileExists(atPath: transcript.path) {
                    let sample = #"{"type":"assistant","uuid":"welcome","message":{"content":[{"type":"text","text":"Welcome to **cmux remote**. Pairing, history and sending are running through your local Bridge."}]}}"# + "\n"
                    try Data(sample.utf8).write(to: transcript)
                }
                cmux = DemoCmux(transcript: transcript.path, project: directory.path); roots = [directory]
            } else {
                let socket = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: runtimeEnvironment, home: home)
                let cli = options.value("cli") ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
                if !options.contains("direct-socket"), FileManager.default.isExecutableFile(atPath: cli) { cmux = CLIControlClient(executable: URL(fileURLWithPath: cli), socketPath: socket, environment: runtimeEnvironment) }
                else { cmux = UnixSocketClient(path: socket, password: runtimeEnvironment["CMUX_REMOTE_SOCKET_PASSWORD"], capability: runtimeEnvironment["CMUX_SOCKET_CAPABILITY"]) }
                roots = [URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path), URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)]
            }
            if command == "resident" { _ = try await cmux.request("system.ping", params: [:]) }
            let lease = try BridgeRunLease(directory: state.directory)
            defer { withExtendedLifetime(lease) {} }
            let mutations = MutationLedger(directory: state.directory)
            let service = SessionService(cmux: cmux, home: home, transcriptRoots: roots, mutations: mutations)
            let events: Task<Void, Never>?
            if options.contains("demo") { events = nil }
            else {
                let socket = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: runtimeEnvironment, home: home)
                let client = CmuxEventClient(path: socket, password: runtimeEnvironment["CMUX_REMOTE_SOCKET_PASSWORD"], capability: runtimeEnvironment["CMUX_SOCKET_CAPABILITY"])
                let monitor = CmuxEventMonitor(repository: CmuxEventCursorRepository(directory: state.directory),
                    consume: { after, frame in try await client.consume(afterSequence: after, onFrame: frame) },
                    invalidate: { await service.invalidateEventBindings() }, refresh: { _ = try await service.sessions() },
                    accept: { await service.acceptEvent($0) })
                events = Task { await monitor.run() }
            }
            defer { events?.cancel() }
            let authority = try state.authority(name: options.value("name") ?? Host.current().localizedName ?? "cmux Bridge")
            let discovery = ResidentMacDiscovery(discovery: await MainActor.run { BridgeDiscovery() }, excludingHostID: authority.host.id, enabled: !options.contains("no-discovery"))
            await discovery.start()
            let connections = MacConnectionRepository(directory: state.directory)
            let nativeGroup = NativeRemoteWorkspaceGroup(local: cmux)
            let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            let mirrors = WorkspaceMirrorCoordinator(local: cmux, executable: executable, stateDirectory: state.directory, nativeGroup: nativeGroup,
                checkpoints: MirrorCheckpointRepository(directory: state.directory))
            let authorize: @Sendable (String, String) async throws -> (HostIdentity, any MirrorRemoteControlling) = { host, workspace in
                let connection = try await connections.connection(hostID: host)
                guard connection.grant.value.scope.workspaces.contains(workspace.lowercased()), connection.grant.value.scope.capabilities.contains(.terminalRead) else {
                    throw BridgeError("scope_denied", "Approve this workspace for terminal viewing first.", status: 403)
                }
                return (connection.host, try RemoteMirrorClient(connection: connection))
            }
            _ = try await mirrors.restore(authorize: authorize)
            let catalog = NativeWorkspaceCatalog(local: cmux, repository: NativeWorkspaceRepository(directory: state.directory), mirrors: mirrors,
                grouping: nativeGroup, executable: executable, stateDirectory: state.directory, authorize: authorize)
            let mac = MacCompanionService(repository: connections, mirrors: mirrors, discovery: discovery, catalog: catalog)
            let sharing = ManagedSharingService(state: state, authority: authority,
                router: BridgeRouter(service: service, authority: authority, legacyToken: options.contains("legacy") ? try state.token() : nil, mirrors: RemoteMirrorService(cmux: cmux, mutations: mutations)),
                listen: options.value("listen") ?? (command == "resident" || options.contains("pair") ? "0.0.0.0" : "127.0.0.1"), port: port, advertise: !options.contains("no-discovery"))
            let ready = AsyncThrowingStream<Void, any Error>.makeStream()
            let owner = Task {
                do { try await OwnerControlServer().run(path: state.directory.appendingPathComponent("owner.sock").path, authority: authority, service: service, mac: mac, sharing: sharing, onListening: { ready.continuation.yield(()); ready.continuation.finish() }) }
                catch { ready.continuation.finish(throwing: error); throw error }
            }
            defer { owner.cancel() }
            var iterator = ready.stream.makeAsyncIterator(); _ = try await iterator.next()
            await mac.start()
            let qr: String?
            if options.contains("pair") {
                guard let host = options.value("host") ?? LANAddressResolver().address() else { throw BridgeError("lan_unavailable", "No private LAN address was found. Connect to Wi-Fi or pass --host.") }
                let workspaces = try await service.workspaces()["workspaces"].array?.compactMap { $0["id"].string } ?? []
                let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: host, port: port), workspaces: workspaces)
                qr = try TerminalQRCode().render(EnrollmentLinkCodec().encode(bootstrap))
            } else { qr = nil }
            if command == "serve" { _ = try await sharing.start() }
            if let qr { print("Scan to request enrollment, then approve that exact device using enrollment pending/approve."); print(qr) }
            // Resident owner/discovery/mirror services stay alive while LAN sharing is off.
            try await owner.value
        case "doctor":
            let path = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home)
            let client: any CmuxControlling
            let cli = options.value("cli") ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
            if !options.contains("direct-socket"), FileManager.default.isExecutableFile(atPath: cli) { client = CLIControlClient(executable: URL(fileURLWithPath: cli), socketPath: path) }
            else { client = UnixSocketClient(path: path, password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"]) }
            _ = try await client.request("system.ping", params: [:]); print("cmux socket is reachable.")
        default:
            print("cmux-remote setup|resident|init|serve|pairing|enrollment|clients|discover|connect|mirror|doctor [--pair] [--legacy] [--no-discovery] [--state PATH] [--socket PATH] [--cli PATH] [--direct-socket] [--listen HOST] [--host HOST] [--port PORT] [--format json] [--demo]")
        }
    }
}
