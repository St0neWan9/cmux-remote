import Foundation
import Darwin
import CmuxRemoteCore
import CmuxRemoteBridge

/// Isolated Bridge for testing the Android enrollment and read/write paths.
///
/// It runs the real `ConnectionAuthority`, `SessionService` and `HTTPServer`,
/// with a deterministic in-memory cmux stand-in. No installed cmux process is
/// read, written or restarted, and no Agent runs.
///
/// Usage:
///   enrollment-fixture <state-dir> <port> [--auto-approve <seconds>]
///
/// It prints `enroll=<cmux-remote://enroll...>` once the window is open.
private actor FixtureCmx: CmuxControlling {
    let workspace = "11111111-1111-1111-1111-111111111111"
    let surface = "22222222-2222-2222-2222-222222222222"
    let root: URL
    /// Flips to false on interrupt, so a test can see the stop land.
    private var working: Bool
    var pendingQuestion = true
    var pendingPermission = true
    private(set) var startedInput: String?
    init(root: URL, working: Bool) { self.root = root; self.working = working }

    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping": return .object(["pong": .bool(true)])
        case "system.capabilities": return .object(["methods": .array([])])
        case "workspace.list":
            return .object(["workspaces": .array([.object(["id": .string(workspace), "title": .string("android-fixture"), "current_directory": .string(root.path)])])])
        case "vault.sessions":
            return .object(["sessions": .array([.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "title": .string("Android enrollment fixture"), "cwd": .string(root.path), "file": .string(root.appendingPathComponent("chat.jsonl").path)])])])
        case "chat.sessions.dump":
            return .object(["sessions": .array([.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string(working ? "working" : "idle"), "cwd": .string(root.path)])])])
        case "system.tree":
            let surfaceRow: JSONValue = .object(["id": .string(surface), "type": .string("terminal"), "title": .string("Android enrollment fixture")])
            return .object(["windows": .array([.object(["workspaces": .array([.object(["id": .string(workspace), "title": .string("android-fixture"), "panes": .array([.object(["id": .string(surface), "surfaces": .array([surfaceRow])])])])])])])])
        case "surface.input_state":
            return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string(surface), "blocks_typing": .bool(false)])
        case "surface.read_text":
            return .object(["text": .string("")])
        case "feed.list":
            var listed: [JSONValue] = []
            if pendingPermission {
                listed.append(.object([
                    "id": .string("fixture-permission"), "request_id": .string("fixture-permission"),
                    "kind": .string("permissionRequest"), "status": .string("pending"), "title": .string("允许构建"),
                    "tool_name": .string("Bash"), "tool_input": .string("swift build"),
                    "workstream_id": .string("cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data("fixture-session".utf8).base64EncodedString()),
                ]))
            }
            guard pendingQuestion else { return .object(["items": .array(listed)]) }
            let question: JSONValue = .object([
                "id": .string("q"),
                "prompt": .string("用哪个方案?"),
                "multi_select": .bool(false),
                "options": .array([
                    .object(["id": .string("a"), "label": .string("快速方案")]),
                    .object(["id": .string("b"), "label": .string("稳妥方案")]),
                ]),
            ])
            listed.append(.object([
                "id": .string("fixture-question"), "request_id": .string("fixture-question"),
                "kind": .string("question"), "status": .string("pending"), "title": .string("用哪个方案?"),
                "workstream_id": .string("cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data("fixture-session".utf8).base64EncodedString()),
                "questions": .array([question]),
            ]))
            return .object(["items": .array(listed)])
        case "feed.question.reply":
            pendingQuestion = false
            return .object(["delivered": .bool(true)])
        case "feed.permission.reply", "feed.exit_plan.reply":
            pendingPermission = false
            return .object(["delivered": .bool(true)])
        case "mobile.chat.send":
            let text = params["text"]?.string ?? ""
            try Self.append([
                #"{"type":"user","uuid":"android-user","timestamp":"2026-10-30T01:00:00Z","message":{"content":"__TEXT__"}}"#,
                #"{"type":"assistant","uuid":"android-reply","timestamp":"2026-10-30T01:00:02Z","message":{"content":[{"type":"text","text":"fixture reply"}]}}"#,
            ], text: text, to: root.appendingPathComponent("chat.jsonl"))
            return .object(["submitted": .bool(true)])
        case "mobile.terminal.rename", "tab.rename":
            return .object(["renamed": .bool(true)])
        // A new terminal is recorded only: the fixture starts no shell and no agent.
        case "surface.create":
            guard let input = params["initial_input"]?.string else { throw BridgeError("invalid_params", "fixture") }
            let started = root.appendingPathComponent("started.jsonl")
            if !FileManager.default.fileExists(atPath: started.path) {
                try Data((#"{"type":"user","uuid":"started","timestamp":"2026-10-30T02:00:00Z","message":{"content":"started"}}"# + "\n").utf8).write(to: started)
            }
            startedInput = input
            return .object(["surface_id": .string("77777777-7777-7777-7777-777777777777")])
        case "mobile.chat.interrupt":
            working = false
            return .object(["interrupted": .bool(true)])
        default: throw BridgeError("unsupported", "The fixture does not implement \(method).")
        }
    }

    private static func append(_ rows: [String], text: String, to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file) }
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }; try handle.seekToEnd()
        for row in rows {
            let line = row.replacingOccurrences(of: "__TEXT__", with: text.replacingOccurrences(of: "\"", with: "\\\""))
            try handle.write(contentsOf: Data((line + "\n").utf8))
        }
    }
}

/// A line the test harness can read while the server keeps running.
private func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

@main private struct EnrollmentFixture {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { throw BridgeError("invalid_input", "Pass a state directory and a port.") }
        let directory = URL(fileURLWithPath: arguments[1])
        guard let port = Int(arguments[2]), (1...65535).contains(port) else { throw BridgeError("invalid_input", "Pass a valid port.") }
        var autoApprove: Int?
        if let index = arguments.firstIndex(of: "--auto-approve"), index + 1 < arguments.count {
            autoApprove = Int(arguments[index + 1])
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        BridgeLog.shared.configure(directory: directory)
        let state = BridgeState(directory: directory)
        if !FileManager.default.fileExists(atPath: state.certificate) { try state.initialize() }
        let root = directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) {
            try Data("# Android fixture project\n".utf8).write(to: readme)
            for arguments in [["init", "--quiet", root.path],
                              ["-C", root.path, "add", "README.md"],
                              ["-C", root.path, "-c", "user.name=Android fixture", "-c", "user.email=fixture@example.invalid",
                               "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "baseline"]] {
                let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git"); git.arguments = arguments
                try git.run(); git.waitUntilExit()
            }
            try Data("# Android fixture project\n\nThis line changed for the diff test.\n".utf8).write(to: readme)
        }
        let transcript = root.appendingPathComponent("chat.jsonl")
        if !FileManager.default.fileExists(atPath: transcript.path) {
            // A real picture, so the preview has something to show and to bound.
            let icon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-v3.png")
            let sample = (try? Data(contentsOf: icon)) ?? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1cAAAAASUVORK5CYII=")!
            let imageRow = #"{"type":"user","uuid":"img","timestamp":"2026-10-30T01:00:03Z","message":{"content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"__IMG__"}}]}}"#
                .replacingOccurrences(of: "__IMG__", with: sample.base64EncodedString())
            try Data([
                #"{"type":"user","uuid":"u1","timestamp":"2026-10-30T01:00:00Z","message":{"content":"你好，Android"}}"#,
                #"{"type":"assistant","uuid":"a1","timestamp":"2026-10-30T01:00:02Z","message":{"content":[{"type":"text","text":"这是隔离 Bridge 的示例回复。"}]}}"#,
                imageRow,
            ].joined(separator: "\n").appending("\n").utf8).write(to: transcript)
        }

        let authority = try state.authority(name: "Android fixture Mac")
        let backend = FixtureCmx(root: root, working: arguments.contains("--working"))
        let service = SessionService(cmux: backend, home: FileManager.default.homeDirectoryForCurrentUser, transcriptRoots: [root], journal: try MutationJournal(file: directory.appendingPathComponent("operations.json")))
        let launcher = SessionLauncher(cmux: backend, home: FileManager.default.homeDirectoryForCurrentUser, mutations: MutationLedger(), sessions: { try await service.sessions() })
        let endpoint = BridgeEndpoint(host: "127.0.0.1", port: port)
        let workspace = await backend.workspace
        let bootstrap = try await authority.open(endpoint: endpoint, workspaces: [workspace], seconds: 600)
        emit("enroll=" + (try EnrollmentLinkCodec().encode(bootstrap)))
        emit("fixture ready on https://127.0.0.1:\(port)")

        if autoApprove != nil {
            // Stands in for the owner: approve whatever is pending, for the life of the fixture.
            Task {
                var approved = Set<String>()
                while true {
                    try? await Task.sleep(for: .seconds(2))
                    for request in await authority.pendingRequests() where !approved.contains(request.requestID) {
                        if (try? await authority.approve(requestID: request.requestID, scope: request.scope)) != nil {
                            approved.insert(request.requestID)
                            emit("auto-approved \(request.requestID)")
                        }
                    }
                }
            }
        }

        try await HTTPServer().run(host: "127.0.0.1", port: port, certificate: state.certificate, key: state.key,
                                   router: BridgeRouter(service: service, authority: authority, launcher: launcher))
    }
}
