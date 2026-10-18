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
    /// Set once the phone starts a session; the new conversation is then bound to `startedSurface`.
    private var started: (agent: String, cwd: String)?
    private let startedSurface = "77777777-7777-7777-7777-777777777777"
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
        self.inlineQuestion = .object([
            "id": .string("inline-question"), "request_id": .string("inline-question"),
            "workstream_id": .string(workstream), "source": .string("claude"),
            "kind": .string("question"), "status": .string("pending"), "title": .string("Agent 提问"),
            "questions": .array([
                .object([
                    "id": .string("plan"), "prompt": .string("用哪个方案?"), "multi_select": .bool(false),
                    "options": .array([
                        .object(["id": .string("fast"), "label": .string("快速方案"), "description": .string("优先速度，改动较小，适合先验证想法")]),
                        .object(["id": .string("safe"), "label": .string("稳妥方案"), "description": .string("优先稳定性，改动更完整，测试覆盖更多")]),
                    ]),
                ]),
            ]),
        ])
    }
    /// A request that asked two questions: the first card carries both and the second is not repeated.
    ///
    /// Shaped as a cmux-tui terminal menu offers it: only its own options answer, nothing can be typed or skipped.
    private var multiQuestion: JSONValue = .object([
        "id": .string("multi-question"), "request_id": .string("multi-question"),
        "workstream_id": .string("cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data("fixture-session".utf8).base64EncodedString()),
        "source": .string("claude"), "kind": .string("question"), "status": .string("pending"), "title": .string("Agent 提问"),
        "questions": .array([
            .object(["id": .string("plan"), "prompt": .string("用哪个方案?"), "multi_select": .bool(false),
                     "allow_custom": .bool(false), "allow_skip": .bool(false),
                     "options": .array([.object(["id": .string("fast"), "label": .string("快速方案")]),
                                        .object(["id": .string("safe"), "label": .string("稳妥方案")])])]),
            .object(["id": .string("scope"), "prompt": .string("改动范围?"), "multi_select": .bool(false),
                     "allow_custom": .bool(false), "allow_skip": .bool(false),
                     "options": .array([.object(["id": .string("front"), "label": .string("只改前端"), "description": .string("只动手机界面，不改 Bridge")]),
                                        .object(["id": .string("both"), "label": .string("前后端都改"), "description": .string("手机和 Bridge 一起改，需要重装桌面端")])])]),
        ]),
    ])
    /// The request the `awaiting-question` transcript's card answers; listed only under that flag.
    private var inlineQuestion: JSONValue
    /// A terminal dialog that only waits for Enter or Escape, shaped exactly as the Bridge's own prompt payload.
    ///
    /// The keys are what the Bridge sends, so a screen line can never become input: the phone only posts the
    /// label it chose and the Bridge maps it back to the key it parsed.
    private var continueNotice: JSONValue = .object([
        "request_id": .string("tui-notice"), "kind": .string("question"), "status": .string("pending"),
        "source": .string("claude"), "workspace_id": .string("11111111-1111-1111-1111-111111111111"),
        "workstream_id": .string("cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data("fixture-session".utf8).base64EncodedString()),
        "title": .string("Claude Code"), "body": .string("We're changing auto mode to no longer charge for classifier requests.\n\nPress Enter to continue\nEsc to cancel"),
        "questions": .array([.object([
            "id": .string("continue"), "prompt": .string("终端正在等待你的选择"), "multi_select": .bool(false),
            "allow_custom": .bool(false), "allow_skip": .bool(false),
            "options": .array([.object(["id": .string("enter"), "label": .string("继续")]),
                               .object(["id": .string("escape"), "label": .string("取消")])]),
        ])]),
    ])
    /// The vault title; a `no-vault-title` file stands in for a session cmux has not named.
    private var vaultTitle: String {
        if flag("no-vault-title") { return "" }
        return (try? String(contentsOf: root.deletingLastPathComponent().appendingPathComponent("vault-title"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "UI 测试：连接与页面"
    }
    /// Opt-in fixture behaviors, switched by an empty file in the state directory or by the launch
    /// environment, so a UI test can select them without guessing where the fixture keeps its state.
    private func flag(_ name: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment["CMUX_REMOTE_FIXTURE_FLAGS"] ?? ""
        if environment.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(name) { return true }
        return FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent(name).path)
    }
    private static func append(_ rows: [JSONValue], to transcript: URL) throws {
        let handle = try FileHandle(forWritingTo: transcript); defer { try? handle.close() }; try handle.seekToEnd()
        for row in rows { var data = try JSONEncoder().encode(row); data.append(10); try handle.write(contentsOf: data) }
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping": return .object(["pong": .bool(true)])
        case "system.capabilities": return .object(["methods": .array([])])
        case "workspace.list":
            var listed: [JSONValue] = [.object(["id": .string(workspace), "title": .string("UI fixture workspace"), "current_directory": .string(root.path)])]
            // A second, empty workspace, so a test can choose between the Mac's workspaces.
            if flag("two-workspaces") { listed.append(.object(["id": .string("33333333-3333-3333-3333-333333333333"), "title": .string("Second workspace"), "current_directory": .string(root.path)])) }
            return .object(["workspaces": .array(listed)])
        case "vault.sessions":
            var rows: [JSONValue] = [.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "title": .string(vaultTitle), "cwd": .string(root.path), "file": .string(transcript.path)])]
            // An Agent that exited while its terminal stayed open: the phone should offer to reopen it.
            if flag("resumable-session") {
                // A resumable conversation is one whose transcript still exists; the fixture writes a short one once.
                let resumed = root.appendingPathComponent("resumable.jsonl")
                if !FileManager.default.fileExists(atPath: resumed.path) {
                    try Data([
                        #"{"type":"user","uuid":"r1","timestamp":"2026-10-12T01:00:00Z","message":{"content":"重启前的问题"}}"#,
                        #"{"type":"assistant","uuid":"r2","timestamp":"2026-10-12T01:00:05Z","message":{"content":"重启前的回答"}}"#,
                    ].joined(separator: "\n").appending("\n").utf8).write(to: resumed)
                }
                rows.append(.object(["session_id": .string("fixture-resumable"), "agent": .string("claude"), "title": .string("UI 测试：可恢复会话"), "cwd": .string(root.path), "file": .string(resumed.path), "resumable": .bool(true)]))
            }
            if let started { rows.append(.object(["session_id": .string("fixture-started"), "agent": .string(started.agent), "title": .string("UI 测试：新会话"), "cwd": .string(started.cwd), "file": .string(root.appendingPathComponent("started.jsonl").path)])) }
            return .object(["sessions": .array(rows)])
        // A started session is only recorded here: no terminal opens and no agent runs.
        case "surface.create":
            guard params["type"]?.string == "terminal", let input = params["initial_input"]?.string, let cwd = params["working_directory"]?.string else { throw BridgeError("invalid_params", "fixture") }
            started = (String(input.split(separator: " ").first ?? "claude").trimmingCharacters(in: .newlines), cwd)
            try Data((#"{"type":"user","uuid":"started","timestamp":"2026-10-12T02:00:00Z","message":{"content":"新会话已在 Mac 上启动"}}"# + "\n").utf8).write(to: root.appendingPathComponent("started.jsonl"))
            return .object(["surface_id": .string(startedSurface)])
        case "system.tree":
            // The tab name stands in for a cmux rename, which the bridge reads from the tree.
            let configured = try? String(contentsOf: root.deletingLastPathComponent().appendingPathComponent("tab-title"), encoding: .utf8)
            let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = trimmed.isEmpty ? "UI 测试：连接与页面" : trimmed
            let surfaceRow: JSONValue = .object(["id": .string(surface), "type": .string("terminal"), "title": .string(title)])
            let paneRow: JSONValue = .object(["id": .string(surface), "surfaces": .array([surfaceRow])])
            let workspaceRow: JSONValue = .object(["id": .string(workspace), "title": .string("UI fixture workspace"), "panes": .array([paneRow])])
            return .object(["windows": .array([.object(["workspaces": .array([workspaceRow])])])])
        case "chat.sessions.dump":
            var rows: [JSONValue] = [.object(["session_id": .string("fixture-session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string(flag("report-working") ? "working" : "idle"), "cwd": .string(root.path)])]
            if let started { rows.append(.object(["session_id": .string("fixture-started"), "agent": .string(started.agent), "workspace_id": .string(workspace), "surface_id": .string(startedSurface), "state": .string("idle"), "cwd": .string(started.cwd)])) }
            if flag("resumable-session") {
                rows.append(.object(["session_id": .string("fixture-resumable"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("88888888-8888-8888-8888-888888888888"), "state": .string("ended"), "cwd": .string(root.path), "resumable": .bool(true)]))
            }
            return .object(["sessions": .array(rows)])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string(surface), "blocks_typing": .bool(false)])
        // The agent's working line lives only on the rendered screen, and the screen also carries the
        // terminal's own chrome, so the fixture renders both exactly as a live terminal would.
        case "surface.read_text":
            guard flag("report-working") else { return .object(["text": .string("")]) }
            return .object(["text": .string([
                "⏺ The table now fits the message width.",
                "✔ Update installed · Restart to update",
                "╭──────────────────────────────────────╮",
                "│ ❯                                    │",
                "╰──────────────────────────────────────╯",
                "✻ Blanching… (54s · ↓ 2.3k tokens)",
            ].joined(separator: "\n"))])
        case "feed.list":
            // The inline question is listed only where its matching transcript card was seeded.
            var listed = items
            if flag("awaiting-question") { listed = [inlineQuestion, continueNotice] + listed }
            if flag("awaiting-multi-question") { listed = [multiQuestion] + listed }
            return .object(["items": .array(listed)])
        case "feed.permission.reply", "feed.exit_plan.reply", "feed.question.reply":
            guard let id = params["request_id"]?.string else { throw BridgeError("request_expired", "Fixture request ended") }
            // The inline question is answered where `feed.list` showed it, not only in the static items.
            if id == "tui-notice", flag("awaiting-question") {
                // Recording the decision is what a real Feed does; a still-pending item would offer it again.
                var fields = continueNotice.object ?? [:]
                fields["status"] = .string("resolved"); fields["decision"] = .object(params)
                continueNotice = .object(fields)
                return .object(["delivered": .bool(true)])
            }
            if id == "multi-question", flag("awaiting-multi-question"), multiQuestion["status"].string == "pending" {
                var fields = multiQuestion.object ?? [:]
                fields["status"] = .string("resolved"); fields["decision"] = .object(params)
                multiQuestion = .object(fields)
                return .object(["delivered": .bool(true)])
            }
            if id == "inline-question", flag("awaiting-question"), inlineQuestion["status"].string == "pending" {
                // Recording the decision is what a real Feed does; a still-pending item would offer the card again.
                var fields = inlineQuestion.object ?? [:]
                fields["status"] = .string("resolved"); fields["decision"] = .object(params)
                inlineQuestion = .object(fields)
                return .object(["delivered": .bool(true)])
            }
            guard let index = items.firstIndex(where: { $0["request_id"].string == id && $0["status"].string == "pending" }), var fields = items[index].object else { throw BridgeError("request_expired", "Fixture request ended") }
            fields["status"] = .string("resolved"); fields["decision"] = .object(params); items[index] = .object(fields)
            if id == "question" {
                var next = fields; next["id"] = .string("question-next"); next["request_id"] = .string("question-next"); next["status"] = .string("pending"); next["title"] = .string("UI 测试：新问题不继承旧选项"); next.removeValue(forKey: "decision"); items.insert(.object(next), at: 0)
            } else if id == "question-next" {
                var next = fields; next["id"] = .string("question-empty"); next["request_id"] = .string("question-empty"); next["status"] = .string("pending"); next["title"] = .string("UI 测试：无选项可空提交"); next["questions"] = .array([.object(["id": .string("empty"), "prompt": .string("可直接提交空回答"), "options": .array([])])]); next.removeValue(forKey: "decision"); items.insert(.object(next), at: 0)
            }
            return .object(["delivered": .bool(true)])
        case "mobile.chat.interrupt": return .object(["interrupted": .bool(true)])
        // Reopening is recorded only; the fixture starts no agent and opens no terminal.
        case "mobile.chat.resume":
            guard params["session_id"]?.string != nil else { throw BridgeError("invalid_params", "fixture") }
            return .object(["surface_id": .string("99999999-9999-9999-9999-999999999999")])
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
            // Claude Code records its model command as command output rather than a prompt; no agent is switched.
            if images.isEmpty, input.hasPrefix("/model ") {
                let name = String(input.dropFirst("/model ".count))
                let command: JSONValue = .object(["type": .string("user"), "uuid": .string(UUID().uuidString), "timestamp": .string(stamp), "message": .object(["role": .string("user"), "content": .string("<command-name>/model</command-name>\n            <command-message>model</command-message>\n            <command-args>\(name)</command-args>")])])
                let output: JSONValue = .object(["type": .string("user"), "uuid": .string(UUID().uuidString), "timestamp": .string(stamp), "message": .object(["role": .string("user"), "content": .string("<local-command-stdout>Set model to `\(name)` and saved as your default for new sessions</local-command-stdout>")])])
                try Self.append([command, output], to: transcript)
                return .object(["submitted": .bool(true)])
            }
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
        // The Bridge's journal refuses a state directory anyone else can reach, and a directory made by `mkdir`
        // under `/tmp` is world-readable: every reply would fail with `journal_unavailable`. The fixture owns the
        // directory it was given, so it closes it rather than making each caller remember to.
        try FileManager.default.createDirectory(at: state.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: state.directory.path)
        if !FileManager.default.fileExists(atPath: state.certificate) { try state.initialize() }
        let root = state.directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Empty folders for the new-session folder browser; version control does not list them as changes.
        for folder in ["Sources/App", "docs"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
        let file = root.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data("# UI fixture project\n\nThis is isolated test content.\n".utf8).write(to: file)
            for arguments in [["init", "--quiet", root.path], ["-C", root.path, "add", "README.md"], ["-C", root.path, "-c", "user.name=UI fixture", "-c", "user.email=ui-fixture@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "UI fixture baseline"]] {
                let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git"); git.arguments = arguments; try git.run(); git.waitUntilExit()
                guard git.terminationStatus == 0 else { throw BridgeError("fixture_setup", "Unable to initialize fixture repository") }
            }
            try Data("# UI fixture project\n\nThis content changed for the isolated diff test.\n".utf8).write(to: file)
        }
        // A transcript shape is chosen the same way the backend picks behaviors: an empty file in the state
        // directory, or a launch-environment flag (the UI test sets the environment, not the fixture).
        // Only the state directory decides the shape: the fixture process does not inherit the test's launch
        // environment, and a decision split between the two would serve one transcript while testing another.
        func selfFlag(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: state.directory.appendingPathComponent(name).path)
        }
        // Each transcript shape gets its own file, so switching a flag on an existing state directory still
        // shows that shape instead of the one written first.
        let shape = selfFlag("short-conversation") ? "chat-short.jsonl"
            : selfFlag("tall-reply") ? "chat-tall.jsonl"
            : selfFlag("awaiting-question") ? "chat-question.jsonl"
            : selfFlag("awaiting-multi-question") ? "chat-multi-question.jsonl"
            : selfFlag("long-conversation") ? "chat-long.jsonl" : "chat.jsonl"
        let transcript = root.appendingPathComponent(shape)
        if !FileManager.default.fileExists(atPath: transcript.path) {
            let icon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-v3.png")
            let sample = (try? Data(contentsOf: icon)) ?? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1cAAAAASUVORK5CYII=")!
            let read: [String: Any] = ["type": "assistant", "uuid": "design-tool", "timestamp": "2026-10-12T01:00:02Z", "message": ["content": [["type": "tool_use", "id": "design-read", "name": "Read", "input": ["file_path": file.path]]]]]
            let image: [String: Any] = ["type": "user", "uuid": "design-image", "timestamp": "2026-10-12T01:00:04Z", "message": ["content": [["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": sample.base64EncodedString()]]]]]
            let readText = String(decoding: try JSONSerialization.data(withJSONObject: read), as: UTF8.self)
            let imageText = String(decoding: try JSONSerialization.data(withJSONObject: image), as: UTF8.self)
            // Earlier turns fill more than two history pages, so reading back has pages to load.
            let earlier = (1...260).map { index in
                let role = index % 2 == 1 ? "user" : "assistant"
                let text = String(format: "历史消息 %04d", index)
                let content = role == "user" ? "\"\(text)\"" : "[{\"type\":\"text\",\"text\":\"\(text)\"}]"
                return "{\"type\":\"\(role)\",\"uuid\":\"earlier-\(index)\",\"timestamp\":\"2026-10-11T01:00:00Z\",\"message\":{\"content\":\(content)}}"
            }
            // Opening anchors are measured on two shapes: a conversation shorter than the page, and one whose
            // newest reply is taller than the page (its first line must still be on screen).
            if selfFlag("short-conversation") {
                let rows = [
                    #"{"type":"user","uuid":"short-user","timestamp":"2026-10-12T01:00:00Z","message":{"content":"当前目录是啥"}}"#,
                    #"{"type":"assistant","uuid":"short-reply","timestamp":"2026-10-12T01:00:02Z","message":{"content":[{"type":"text","text":"The user asks what the current directory is, and I answer with /Users/valuz/projects/cmux-remote in `/Users/valuz/projects/cmux-remote`, 当前在 claude/compaction-binding 分支上。"}]}}"#,
                    #"{"type":"system","subtype":"turn_duration","durationMs":7000,"timestamp":"2026-10-12T01:00:03Z"}"#]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            } else if selfFlag("awaiting-question") {
                let ask: [String: Any] = ["type": "assistant", "uuid": "ask", "timestamp": "2026-10-12T01:00:02Z",
                                          "message": ["content": [["type": "tool_use", "id": "ask-plan", "name": "AskUserQuestion",
                                                                  "input": ["questions": [["question": "用哪个方案?",
                                                                                           "options": [["label": "快速方案"], ["label": "稳妥方案"]]]]]]]]]
                let askText = String(decoding: try JSONSerialization.data(withJSONObject: ask), as: UTF8.self)
                let rows = [
                    #"{"type":"user","uuid":"ask-user","timestamp":"2026-10-12T01:00:00Z","message":{"content":"帮我选个方案"}}"#,
                    askText]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            } else if selfFlag("awaiting-multi-question") {
                let ask: [String: Any] = ["type": "assistant", "uuid": "ask-multi", "timestamp": "2026-10-12T01:00:02Z",
                                          "message": ["content": [["type": "tool_use", "id": "ask-multi-plan", "name": "AskUserQuestion",
                                                                  "input": ["questions": [
                                                                    ["question": "用哪个方案?", "options": [["label": "快速方案"], ["label": "稳妥方案"]]],
                                                                    ["question": "改动范围?", "options": [["label": "只改前端"], ["label": "前后端都改"]]]]]]]]]
                let askText = String(decoding: try JSONSerialization.data(withJSONObject: ask), as: UTF8.self)
                // Earlier turns make the page taller than the screen, so the form can pass under the header and composer.
                let rows = earlier.suffix(30) + [
                    #"{"type":"user","uuid":"ask-multi-user","timestamp":"2026-10-12T01:00:00Z","message":{"content":"帮我选个方案和范围"}}"#,
                    askText]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            } else if selfFlag("long-conversation") {
                // The newest turn ends in a short reply, so it carries the transcript's own action row: the
                // page's end is then that row plus the page's foot, which is what a reader scrolling to the
                // bottom must be able to see whole.
                let rows = earlier + [
                    #"{"type":"user","uuid":"long-user","timestamp":"2026-10-12T01:00:00Z","message":{"content":"最后确认一下"}}"#,
                    #"{"type":"assistant","uuid":"long-reply","timestamp":"2026-10-12T01:00:02Z","message":{"content":[{"type":"text","text":"好的，改完了，最后一行的按钮必须完整露在输入框上方。"}]}}"#,
                    #"{"type":"system","subtype":"turn_duration","durationMs":6000,"timestamp":"2026-10-12T01:00:03Z"}"#]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            } else if selfFlag("tall-reply") {
                // A JSON string cannot hold a raw newline: the transcript is one row per line.
                let body = (1...28).map { "第 \($0) 行:这是一段用来撑高的正文内容。" }.joined(separator: "\\n")
                let rows = earlier + [
                    #"{"type":"user","uuid":"tall-user","timestamp":"2026-10-12T01:00:00Z","message":{"content":"当前目录是啥"}}"#,
                    "{\"type\":\"assistant\",\"uuid\":\"tall-reply\",\"timestamp\":\"2026-10-12T01:00:02Z\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"\(body)\"}]}}"]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            } else {
                let rows = earlier + [
                #"{"type":"user","uuid":"u","timestamp":"2026-10-12T01:00:00Z","message":{"content":"检查本地连接和页面样式"}}"#,
                readText,
                ##"{"type":"user","uuid":"design-result","timestamp":"2026-10-12T01:00:03Z","message":{"content":[{"type":"tool_result","tool_use_id":"design-read","content":"# UI fixture project\n\nLeft aligned file contents.\n"}]}}"##,
                imageText,
                #"{"type":"assistant","uuid":"a","timestamp":"2026-10-12T01:00:05Z","message":{"content":[{"type":"text","text":"页面使用白色背景，按钮和输入框悬浮显示。这个测试环境不会启动智能体，也不会更改真实权限。"}]}}"#,
                // A reply with a pipe table: its columns must keep their own rendering when the text is selected.
                #"{"type":"assistant","uuid":"table","timestamp":"2026-10-12T01:00:07Z","message":{"content":[{"type":"text","text":"| 项目 | 结果 |\n| --- | --- |\n| 构建 | 通过 |\n| 测试 | 通过 |"}]}}"#,
                #"{"type":"system","subtype":"turn_duration","durationMs":5000,"timestamp":"2026-10-12T01:00:06Z"}"#]
                try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
            }
        }
        let pairing = try state.pairing(host: "127.0.0.1", port: port)
        let configuration = state.directory.appendingPathComponent("phone.json")
        try JSONEncoder().encode(pairing).write(to: configuration, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
        let backend = PhoneUIBackend(root: root, transcript: transcript)
        let service = SessionService(cmux: backend, home: FileManager.default.homeDirectoryForCurrentUser, transcriptRoots: [root], journal: try MutationJournal(file: state.directory.appendingPathComponent("operations.json")))
        let launcher = SessionLauncher(cmux: backend, home: FileManager.default.homeDirectoryForCurrentUser, mutations: MutationLedger(), sessions: { try await service.sessions() })
        print("Isolated phone UI fixture listening on loopback port \(port). No real cmux sessions are used.")
        try await HTTPServer().run(host: "127.0.0.1", port: port, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, token: pairing.token, launcher: launcher))
    }
}
