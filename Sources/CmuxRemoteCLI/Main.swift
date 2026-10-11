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
        case "pairing":
            let pairing = try state.pairing(host: options.value("host") ?? "localhost", port: port)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(pairing), as: UTF8.self))
        case "serve":
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
                cmux = UnixSocketClient(path: try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home), password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"])
                roots = [URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path), URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)]
            }
            let service = SessionService(cmux: cmux, home: home, transcriptRoots: roots)
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
            try await HTTPServer().run(host: options.value("listen") ?? "127.0.0.1", port: port, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, token: state.token()))
        case "doctor":
            let path = try SocketDiscovery().resolve(explicit: options.value("socket"), environment: ProcessInfo.processInfo.environment, home: home)
            let client = UnixSocketClient(path: path, password: ProcessInfo.processInfo.environment["CMUX_REMOTE_SOCKET_PASSWORD"])
            _ = try await client.request("system.ping", params: [:]); print("cmux socket is reachable.")
        default:
            print("cmux-remote init|serve|pairing|doctor [--state PATH] [--socket PATH] [--listen HOST] [--host HOST] [--port PORT] [--demo]")
        }
    }
}
