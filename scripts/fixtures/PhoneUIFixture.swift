import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Deterministic UI-only backend. Decisions update this actor's fixture data, never cmux or an agent.
private actor PhoneUIBackend: CmuxControlling {
    let root: URL
    let transcript: URL
    private let workspace = "11111111-1111-1111-1111-111111111111"
    private let surface = "22222222-2222-2222-2222-222222222222"
    private var items: [JSONValue]
    init(root: URL, transcript: URL) {
        self.root = root; self.transcript = transcript
        let questions: [JSONValue] = [
            .object(["id": .string("q1"), "prompt": .string("请选择一个同名选项，验证 ID 不串选"), "multi_select": .bool(false), "options": .array([
                .object(["id": .string("first"), "label": .string("同名选项"), "description": .string("第一个选项")]),
                .object(["id": .string("second"), "label": .string("同名选项"), "description": .string("第二个选项")])])]),
            .object(["id": .string("q2"), "prompt": .string("请选择多个项目，或填写自定义答案"), "multi_select": .bool(true), "options": .array([
                .object(["id": .string("code"), "label": .string("代码")]), .object(["id": .string("tests"), "label": .string("测试")])])])]
        let workstream = "cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data("fixture-session".utf8).base64EncodedString()
        items = [
            .object(["id": .string("question"), "request_id": .string("question"), "workstream_id": .string(workstream), "source": .string("claude"), "kind": .string("question"), "status": .string("pending"), "title": .string("UI 测试：问题表单"), "questions": .array(questions)]),
            .object(["id": .string("permission"), "request_id": .string("permission"), "workstream_id": .string(workstream), "source": .string("claude"), "kind": .string("permissionRequest"), "status": .string("pending"), "tool_name": .string("UI 测试：允许一次"), "tool_input": .string("只记录此测试决策，不执行任何工具。")]),
            .object(["id": .string("plan"), "request_id": .string("plan"), "workstream_id": .string(workstream), "source": .string("claude"), "kind": .string("exitPlan"), "status": .string("pending"), "title": .string("UI 测试：计划反馈"), "plan": .string("1. 验证白色页面\n2. 验证本地表单状态\n\n此计划不会执行代码或修改实际权限。")]),
            .object(["id": .string("result"), "workstream_id": .string(workstream), "source": .string("claude"), "kind": .string("toolResult"), "status": .string("telemetry"), "tool_name": .string("UI 测试：错误结果"), "tool_result": .string("UI_FIXTURE_ERROR_OUTPUT_VISIBLE"), "tool_result_is_error": .bool(true)])]
    }
    /// Opt-in fixture behaviors, switched by an empty file in the state directory.
    private func flag(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent(name).path)
    }
    private static func append(_ rows: [JSONValue], to transcript: URL) throws {
        let handle = try FileHandle(forWritingTo: transcript); defer { try? handle.close() }; try handle.seekToEnd()
        for row in rows { var data = try JSONEncoder().encode(row); data.append(10); try handle.write(contentsOf: data) }
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping": return .object(["pong": .bool(true)])
        case "system.capabilities": return .object(["methods": .array([])])
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspace), "title": .string("UI fixture workspace")])])])
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "title": .string("UI 测试：连接与页面"), "cwd": .string(root.path), "file": .string(transcript.path)])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string(flag("report-working") ? "working" : "idle"), "cwd": .string(root.path)])])])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string(surface), "blocks_typing": .bool(false)])
        case "surface.read_text": return .object(["text": .string("")])
        case "feed.list": return .object(["items": .array(items)])
        case "feed.permission.reply", "feed.exit_plan.reply", "feed.question.reply":
            guard let id = params["request_id"]?.string, let index = items.firstIndex(where: { $0["request_id"].string == id && $0["status"].string == "pending" }), var fields = items[index].object else { throw BridgeError("request_expired", "Fixture request ended") }
            fields["status"] = .string("resolved"); fields["decision"] = .object(params); items[index] = .object(fields)
            if id == "question" {
                var next = fields; next["id"] = .string("question-next"); next["request_id"] = .string("question-next"); next["status"] = .string("pending"); next["title"] = .string("UI 测试：新问题不继承旧选项"); next.removeValue(forKey: "decision"); items.insert(.object(next), at: 0)
            } else if id == "question-next" {
                var next = fields; next["id"] = .string("question-empty"); next["request_id"] = .string("question-empty"); next["status"] = .string("pending"); next["title"] = .string("UI 测试：无选项可空提交"); next["questions"] = .array([.object(["id": .string("empty"), "prompt": .string("可直接提交空回答"), "options": .array([])])]); next.removeValue(forKey: "decision"); items.insert(.object(next), at: 0)
            }
            return .object(["delivered": .bool(true)])
        case "mobile.chat.interrupt": return .object(["interrupted": .bool(true)])
        case "mobile.chat.send":
            let stamp = ISO8601DateFormatter().string(from: Date())
            let images = params["attachments"]?.array ?? []
            let uploads = root.appendingPathComponent("uploads")
            try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var paths: [String] = []
            for image in images {
                guard let raw = image["data_b64"].string, let data = Data(base64Encoded: raw) else { throw BridgeError("invalid_image", "Fixture image invalid") }
                let file = uploads.appendingPathComponent("photo-" + UUID().uuidString + ".jpg")
                try data.write(to: file, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                paths.append(file.path)
            }
            let input = (paths + [params["text"]?.string ?? ""]).joined(separator: " ")
            let user: JSONValue = .object(["type": .string("user"), "uuid": .string(UUID().uuidString), "timestamp": .string(stamp), "message": .object(["content": .string(input)])])
            let replyText = "UI fixture received \(images.count) image(s) and your prompt. No agent was started."
            let reply: JSONValue = .object(["type": .string("assistant"), "uuid": .string(UUID().uuidString), "timestamp": .string(stamp), "message": .object(["content": .array([.object(["type": .string("text"), "text": .string(replyText)])])])])
            let duration: JSONValue = .object(["type": .string("system"), "subtype": .string("turn_duration"), "durationMs": .number(2500), "timestamp": .string(stamp)])
            // An opt-in delay stands in for an agent that records the prompt late, so the phone's pending bubble stays visible.
            if flag("delay-transcript") {
                let transcript = transcript
                Task { try? await Task.sleep(for: .seconds(6)); try? Self.append([user, reply, duration], to: transcript) }
            } else { try Self.append([user, reply, duration], to: transcript) }
            let evidence: JSONValue = .object(["image_count": .number(Double(images.count)), "formats": .array(images.map { $0["format"] }), "text": params["text"] ?? .string("")])
            let observed = root.deletingLastPathComponent().appendingPathComponent("observed-send.json")
            try JSONEncoder().encode(evidence).write(to: observed, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: observed.path)
            let lost = root.deletingLastPathComponent().appendingPathComponent("lose-next-receipt")
            if FileManager.default.fileExists(atPath: lost.path) { try FileManager.default.removeItem(at: lost); throw BridgeError("outcome_unknown", "Fixture lost the mutation receipt", status: 504) }
            return .object(["submitted": .bool(true)])
        default: throw BridgeError("method_not_found", "UI fixture does not implement this method", status: 404)
        }
    }
}

@main private struct PhoneUIFixture {
    static func main() async throws {
        guard (2...3).contains(CommandLine.arguments.count) else { throw BridgeError("invalid_input", "Pass a fixture state directory and optional port") }
        let port = CommandLine.arguments.count == 3 ? (Int(CommandLine.arguments[2]) ?? 0) : 7745
        guard (1...65535).contains(port) else { throw BridgeError("invalid_input", "Pass a valid fixture port") }
        let state = BridgeState(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        if !FileManager.default.fileExists(atPath: state.certificate) { try state.initialize() }
        let root = state.directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data("# UI fixture project\n\nThis is isolated test content.\n".utf8).write(to: file)
            for arguments in [["init", "--quiet", root.path], ["-C", root.path, "add", "README.md"], ["-C", root.path, "-c", "user.name=UI fixture", "-c", "user.email=ui-fixture@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "UI fixture baseline"]] {
                let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git"); git.arguments = arguments; try git.run(); git.waitUntilExit()
                guard git.terminationStatus == 0 else { throw BridgeError("fixture_setup", "Unable to initialize fixture repository") }
            }
            try Data("# UI fixture project\n\nThis content changed for the isolated diff test.\n".utf8).write(to: file)
        }
        let transcript = root.appendingPathComponent("chat.jsonl")
        if !FileManager.default.fileExists(atPath: transcript.path) {
            let icon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-v3.png")
            let sample = (try? Data(contentsOf: icon)) ?? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1cAAAAASUVORK5CYII=")!
            let read: [String: Any] = ["type": "assistant", "uuid": "design-tool", "timestamp": "2026-10-12T01:00:02Z", "message": ["content": [["type": "tool_use", "id": "design-read", "name": "Read", "input": ["file_path": file.path]]]]]
            let image: [String: Any] = ["type": "user", "uuid": "design-image", "timestamp": "2026-10-12T01:00:04Z", "message": ["content": [["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": sample.base64EncodedString()]]]]]
            let readText = String(decoding: try JSONSerialization.data(withJSONObject: read), as: UTF8.self)
            let imageText = String(decoding: try JSONSerialization.data(withJSONObject: image), as: UTF8.self)
            let rows = [
                #"{"type":"user","uuid":"u","timestamp":"2026-10-12T01:00:00Z","message":{"content":"检查本地连接和页面样式"}}"#,
                readText,
                ##"{"type":"user","uuid":"design-result","timestamp":"2026-10-12T01:00:03Z","message":{"content":[{"type":"tool_result","tool_use_id":"design-read","content":"# UI fixture project\n\nLeft aligned file contents.\n"}]}}"##,
                imageText,
                #"{"type":"assistant","uuid":"a","timestamp":"2026-10-12T01:00:05Z","message":{"content":[{"type":"text","text":"页面使用白色背景，按钮和输入框悬浮显示。这个测试环境不会启动智能体，也不会更改真实权限。"}]}}"#,
                #"{"type":"system","subtype":"turn_duration","durationMs":5000,"timestamp":"2026-10-12T01:00:06Z"}"#]
            try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
        }
        let pairing = try state.pairing(host: "127.0.0.1", port: port)
        let configuration = state.directory.appendingPathComponent("phone.json")
        try JSONEncoder().encode(pairing).write(to: configuration, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
        let backend = PhoneUIBackend(root: root, transcript: transcript)
        let service = SessionService(cmux: backend, home: FileManager.default.homeDirectoryForCurrentUser, transcriptRoots: [root], journal: try MutationJournal(file: state.directory.appendingPathComponent("operations.json")))
        print("Isolated phone UI fixture listening on loopback port \(port). No real cmux sessions are used.")
        try await HTTPServer().run(host: "127.0.0.1", port: port, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, token: pairing.token))
    }
}
