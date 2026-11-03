import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Claude Code's AskUserQuestion menu in a daemon terminal is answered from the conversation, by keys only.
///
/// The screens are Claude Code 2.1's own menus, captured from a real run; the key protocol was observed there:
/// a single-choice digit moves on, multi-choice digits toggle and Right moves on, and the review page submits on 1.
@Suite struct TuiAskUserQuestionTests {
    private let twoQuestions = """
    ←  ☐ 方案  ☐ 范围  ✔ Submit  →
    用哪个方案?
    ❯ 1. 快速方案
         优先速度，改动较小
      2. 稳妥方案
         优先稳定性，改动更完整
      3. Type something.
    ──────────────────────────────────────────
      4. Chat about this
    Enter to select · Tab/Arrow keys to navigate · Esc to cancel
    """
    private let oneQuestion = """
     ☐ 继续
    要继续吗?
    ❯ 1. 继续
         继续执行
      2. 停下
         停止当前操作
      3. Type something.
    ──────────────────────────────────────────
      4. Chat about this
    Enter to select · ↑/↓ to navigate · Esc to cancel
    """
    private func call(_ id: String, _ questions: [[String: Any]]) -> String {
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": "AskUserQuestion", "input": ["questions": questions]]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
    }
    private func result(_ id: String) -> String {
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"answered"}]}}"#
    }
    private var plan: [[String: Any]] {
        [["question": "用哪个方案?", "header": "方案", "multiSelect": false, "options": [["label": "快速方案", "description": "优先速度，改动较小"], ["label": "稳妥方案", "description": "优先稳定性，改动更完整"]]],
         ["question": "改动范围?", "header": "范围", "multiSelect": true, "options": [["label": "前端"], ["label": "后端"]]]]
    }
    /// A daemon Agent blocked on `screen`, with `transcript` as its recorded history.
    private func setup(screen: String, transcript: [String]) async throws -> (TuiResourceFixture, TuiControlAdapter, SessionService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("projects/-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data((transcript.joined(separator: "\n") + "\n").utf8).write(to: folder.appendingPathComponent(TuiResourceFixture.providerID + ".jsonl"))
        let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: screen)
        let backend = TuiControlAdapter(client: source, transcripts: .init(claudeRoot: root, codexRoot: URL(fileURLWithPath: "/missing-codex")), decisions: MutationLedger(), keyPause: .milliseconds(1))
        return (source, backend, SessionService(cmux: backend, home: URL(fileURLWithPath: "/fixture"), transcriptRoots: []), root)
    }

    @Test func theConversationCardAnswersEveryQuestionWithMenuKeys() async throws {
        let (source, _, service, root) = try await setup(screen: twoQuestions, transcript: [call("toolu_plan", plan)])
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try #require(try await service.sessions().first)
        let items = try await service.feed()["items"].array ?? []
        // The card in the conversation finds this request by its own prompts, the transcript's exact words.
        let matched = ConversationQuestions().pending(items, agent: record.agent, sessionID: record.id)
        #expect(Set(matched.keys) == ["用哪个方案?", "改动范围?"])
        // The terminal holds the whole conversation above the menu; the Feed list shows the question, not that page.
        #expect(items.first?["body"].string == nil)
        let first = try #require(matched["用哪个方案?"])
        #expect(first.isFirst && first.questions.count == 2)
        #expect(first.questions[1]["multi_select"].bool == true)
        #expect(first.questions[0]["options"].array?.compactMap { $0["label"].string } == ["快速方案", "稳妥方案"])
        // Typing into the menu and cancelling it are not offered: only its own options can answer.
        #expect(first.questions.allSatisfy { $0["allow_custom"].bool == false && $0["allow_skip"].bool == false })

        let access = SessionAccess(clientID: "phone") { capability, workspace in #expect(capability == .feedReply); #expect(workspace == record.workspaceID) }
        _ = try await service.reply(requestID: first.requestID, body: ConversationQuestions().reply(requestID: first.requestID, selections: ["稳妥方案", "前端, 后端"]), access: access)
        // Each key is its own write: a menu ignores keys that arrive together as one pasted string.
        let effects = await source.effects
        #expect(effects.allSatisfy { $0.0 == "terminal.input.keys" })
        #expect(effects.map { $0.1["keys"]?.array ?? [] } == ["2", "1", "2", "right", "1"].map { [JSONValue.string($0)] })
        // Every key carries its own idempotency key, so a replay never re-sends the whole answer as one.
        #expect(Set(effects.compactMap(\.2)).count == 5)
    }

    /// Claude Code wraps a long question inside the menu's box, so its prompt is never one whole screen line.
    /// Captured from a real run on this Mac; the menu is still that request's own menu.
    private let wrappedQuestion = [
        "☐ 对照哪个",
        "",
        "│ 我在所有分支里都没找到「iOS 下拉分页又优化了」对应的提交：RN 端的 MessageList.tsx 和 ChatView.tsx 最后一次动分页是 08-06 的",
        "│ e6c3b650f「support paged mobile chat",
        "│ history」，之后的改动都和分页无关。目前的情况是：RN（iOS/Android）的对话页顶部有「加载更早消息」按钮，按 before_seq 每次取 30",
        "│ 轮，配合 80/40 的渲染窗口；鸿蒙的对话页只加载最近 30 轮，没有加载更早消息的功能，但 API 参数和翻译 key",
        "│ 都已经有了。另外，活动页的历史分页两端都已实现。你说的是哪一个？",
        "",
        "❯ 1. 鸿蒙对话页补齐 RN 分页",
        "     按 RN 现有逻辑（before_seq、30 轮一页、80/40 渲染窗口、prepend",
        "     后保持阅读位置）给鸿蒙对话页加「加载更早消息」，harmony-native-src 和 harmony/entry 两份镜像同步改，并补结构测试",
        "  2. 优化还没推到远端",
        "     这次优化在别的机器或本地分支上，还没 push；请告诉我分支名或 commit，我拉下来再对照",
        "  3. RN 改成下拉自动加载",
        "     把 RN 的按钮改成滚到顶部或下拉时自动加载更早消息（现在测试明确禁止 onScrollToUpper），再同步到鸿蒙",
        "  4. Type something.",
        "───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────",
        "  5. Chat about this",
        "",
        "Enter to select · ↑/↓ to navigate · Esc to cancel",
    ].joined(separator: "\n")
    private let wrappedPrompt = "我在所有分支里都没找到「iOS 下拉分页又优化了」对应的提交：RN 端的 MessageList.tsx 和 ChatView.tsx 最后一次动分页是 08-06 的 e6c3b650f「support paged mobile chat history」，之后的改动都和分页无关。目前的情况是：RN（iOS/Android）的对话页顶部有「加载更早消息」按钮，按 before_seq 每次取 30 轮，配合 80/40 的渲染窗口；鸿蒙的对话页只加载最近 30 轮，没有加载更早消息的功能，但 API 参数和翻译 key 都已经有了。另外，活动页的历史分页两端都已实现。你说的是哪一个？"

    @Test func aMenuThatWrapsItsQuestionIsStillOffered() async throws {
        let ask = [["question": wrappedPrompt, "header": "对照哪个", "multiSelect": false,
                    "options": [["label": "鸿蒙对话页补齐 RN 分页"], ["label": "优化还没推到远端"], ["label": "RN 改成下拉自动加载"]]]]
        let (source, backend, service, root) = try await setup(screen: wrappedQuestion, transcript: [call("toolu_long", ask)])
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try #require(try await service.sessions().first)
        let items = try await service.feed()["items"].array ?? []
        // The card in the conversation finds the request by the transcript's exact words.
        let matched = ConversationQuestions().pending(items, agent: record.agent, sessionID: record.id)
        let match = try #require(matched[wrappedPrompt], "A wrapped question was not offered for an answer")
        _ = try await service.reply(requestID: match.requestID, body: ConversationQuestions().reply(requestID: match.requestID, selections: ["RN 改成下拉自动加载"]))
        #expect(await source.effects.map { $0.1["keys"]?.array ?? [] } == [[.string("3")]])
    }

    @Test func aSingleChoiceQuestionSubmitsWithItsNumberAlone() async throws {
        let ask = [["question": "要继续吗?", "header": "继续", "multiSelect": false, "options": [["label": "继续"], ["label": "停下"]]]]
        let (source, backend, _, root) = try await setup(screen: oneQuestion, transcript: [call("toolu_go", ask)])
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        _ = try await backend.request("feed.question.reply", params: ["request_id": item["request_id"], "selections": .array([.string("停下")])])
        #expect(await source.effects.map { $0.1["keys"]?.array ?? [] } == [[.string("2")]])
    }

    @Test func anAnswerTheMenuDoesNotOfferSendsNothing() async throws {
        let (source, backend, _, root) = try await setup(screen: twoQuestions, transcript: [call("toolu_plan", plan)])
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        for selections in [["稳妥方案"], ["别的方案", "前端"], ["稳妥方案", "前端, 中台"], ["稳妥方案", ""]] {
            await #expect(throws: BridgeError.self) {
                _ = try await backend.request("feed.question.reply", params: ["request_id": item["request_id"], "selections": .array(selections.map(JSONValue.string))])
            }
        }
        #expect(await source.effects.isEmpty)
    }

    @Test func aMenuAlreadyMovedOnOrAnsweredIsNotOffered() async throws {
        // Someone at the Mac answered the first question: the keys would start from the wrong place.
        let moved = twoQuestions.replacingOccurrences(of: "☐ 方案", with: "☒ 方案")
        let (_, partly, _, first) = try await setup(screen: moved, transcript: [call("toolu_plan", plan)])
        defer { try? FileManager.default.removeItem(at: first) }
        #expect(try await partly.request("feed.list", params: [:])["items"].array?.isEmpty == true)
        // The transcript recorded the answer: the menu on screen is not for a request still waiting.
        let (_, answered, _, second) = try await setup(screen: twoQuestions, transcript: [call("toolu_plan", plan), result("toolu_plan")])
        defer { try? FileManager.default.removeItem(at: second) }
        #expect(try await answered.request("feed.list", params: [:])["items"].array?.isEmpty == true)
        // A menu whose first question is not the recorded one belongs to some other prompt.
        let other = [["question": "别的问题?", "multiSelect": false, "options": [["label": "快速方案"], ["label": "稳妥方案"]]]]
        let (_, unrelated, _, third) = try await setup(screen: twoQuestions, transcript: [call("toolu_other", other)])
        defer { try? FileManager.default.removeItem(at: third) }
        #expect(try await unrelated.request("feed.list", params: [:])["items"].array?.isEmpty == true)
    }

    @Test func aChangedScreenBeforeTheAnswerSendsNothing() async throws {
        let (source, backend, _, root) = try await setup(screen: twoQuestions, transcript: [call("toolu_plan", plan)])
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        await source.configure(screen: twoQuestions.replacingOccurrences(of: "❯ 1. 快速方案", with: "  1. 快速方案").replacingOccurrences(of: "  2. 稳妥方案", with: "❯ 2. 稳妥方案"))
        await #expect(throws: BridgeError.self) {
            _ = try await backend.request("feed.question.reply", params: ["request_id": item["request_id"], "selections": .array([.string("稳妥方案"), .string("前端")])])
        }
        #expect(await source.effects.isEmpty)
    }

    @Test func aLabelHoldingTheSeparatorIsMatchedWhole() {
        let request = AskUserQuestionRequest(toolUseID: "t", questions: [
            .init(prompt: "选哪些?", header: nil, options: [.init(label: "a, b", detail: nil), .init(label: "a", detail: nil), .init(label: "b", detail: nil)], multiSelect: true)])
        #expect(request.keys(for: ["a, b"]) == nil, "Either the first option or the second and third: the answer is ambiguous")
        #expect(request.keys(for: ["a, b, a"]) == ["1", "2", "right", "1"])
        #expect(request.keys(for: ["b"]) == ["3", "right", "1"])
    }
}
