import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

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
        switch command {
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
        case "serve":
            if options.contains("pair"), !FileManager.default.fileExists(atPath: state.directory.appendingPathComponent("token").path) { try state.initialize() }
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
                let socket = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home)
                let cli = options.value("cli") ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
                if !options.contains("direct-socket"), FileManager.default.isExecutableFile(atPath: cli) { cmux = CLIControlClient(executable: URL(fileURLWithPath: cli), socketPath: socket) }
                else { cmux = UnixSocketClient(path: socket, password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"]) }
                roots = [URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path), URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)]
            }
            let lease = try BridgeRunLease(directory: state.directory)
            defer { withExtendedLifetime(lease) {} }
            let journal = try MutationJournal(file: state.directory.appendingPathComponent("operations.json"))
            let service = SessionService(cmux: cmux, home: home, transcriptRoots: roots, journal: journal)
            let events: Task<Void, Never>?
            if options.contains("demo") { events = nil }
            else {
                let socket = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home)
                let client = CmuxEventClient(path: socket, password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"])
                events = Task {
                    // A disconnected stream degrades to snapshots. Explicit restart reconnects it.
                    try? await client.consume(afterSequence: await service.eventCursor()) { await service.acceptEvent($0) }
                }
            }
            defer { events?.cancel() }
            let authority = try state.authority(name: options.value("name") ?? Host.current().localizedName ?? "cmux Bridge")
            let ready = AsyncThrowingStream<Void, any Error>.makeStream()
            let owner = Task {
                do { try await OwnerControlServer().run(path: state.directory.appendingPathComponent("owner.sock").path, authority: authority, service: service, onListening: { ready.continuation.yield(()); ready.continuation.finish() }) }
                catch { ready.continuation.finish(throwing: error); throw error }
            }
            defer { owner.cancel() }
            var iterator = ready.stream.makeAsyncIterator(); _ = try await iterator.next()
            let qr: String?
            if options.contains("pair") {
                guard let host = options.value("host") ?? LANAddressResolver().address() else { throw BridgeError("lan_unavailable", "No private LAN address was found. Connect to Wi-Fi or pass --host.") }
                let workspaces = try await service.workspaces()["workspaces"].array?.compactMap { $0["id"].string } ?? []
                let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: host, port: port), workspaces: workspaces)
                qr = try TerminalQRCode().render(EnrollmentLinkCodec().encode(bootstrap))
            } else { qr = nil }
            let advertisement: BonjourAdvertisement?
            if options.contains("no-discovery") { advertisement = nil }
            else {
                do { advertisement = try BonjourAdvertisement(host: authority.host, port: port) }
                catch { advertisement = nil; print("LAN discovery is unavailable; HTTPS and QR enrollment remain enabled.") }
            }
            defer { withExtendedLifetime(advertisement) {} }
            if options.contains("legacy") { print("Legacy shared-token access explicitly enabled; migrate devices to v2 enrollment.") }
            try await HTTPServer().run(host: options.value("listen") ?? (options.contains("pair") ? "0.0.0.0" : "127.0.0.1"), port: port, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, authority: authority, legacyToken: options.contains("legacy") ? try state.token() : nil), onListening: { _ in
                if let qr { print("Scan to request enrollment, then approve that exact device using enrollment pending/approve."); print(qr) }
            })
        case "doctor":
            let path = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home)
            let client: any CmuxControlling
            let cli = options.value("cli") ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
            if !options.contains("direct-socket"), FileManager.default.isExecutableFile(atPath: cli) { client = CLIControlClient(executable: URL(fileURLWithPath: cli), socketPath: path) }
            else { client = UnixSocketClient(path: path, password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"]) }
            _ = try await client.request("system.ping", params: [:]); print("cmux socket is reachable.")
        default:
            print("cmux-remote init|serve|pairing|enrollment|clients|doctor [--pair] [--legacy] [--no-discovery] [--state PATH] [--socket PATH] [--cli PATH] [--direct-socket] [--listen HOST] [--host HOST] [--port PORT] [--format json] [--demo]")
        }
    }
}
