import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct TuiDecisionTests {
    private let screen = "Run command\nDo you want to proceed?\n❯ 1. Yes\n2. Yes, and don't ask again\n3. No\nEsc to cancel\n\n\n\n"
    private func bridge(_ source: TuiResourceFixture, ledger: MutationLedger = MutationLedger()) -> TuiControlAdapter {
        TuiControlAdapter(client: source, transcripts: .init(claudeRoot: URL(fileURLWithPath: "/missing-claude"), codexRoot: URL(fileURLWithPath: "/missing-codex")), decisions: ledger)
    }
    @Test func onceAndDenyUseBoundedExistingFeedAndWorkspaceScope() async throws {
        for mode in ["once", "deny"] {
            let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: screen)
            let backend = bridge(source), service = SessionService(cmux: backend, home: URL(fileURLWithPath: "/fixture"), transcriptRoots: [])
            let record = try #require(try await service.sessions().first)
            let item = try #require(try await service.feed()["items"].array?.first)
            #expect(item["workspace_id"].string == record.workspaceID)
            #expect(FeedDecisionPolicy().modes(for: item) == [.once, .deny])
            let access = SessionAccess(clientID: "phone") { capability, workspace in #expect(capability == .feedReply); #expect(workspace == record.workspaceID) }
            _ = try await service.reply(requestID: item["request_id"].string!, body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string(mode)]), access: access)
            #expect(await source.effects.count == 1)
            let effects = await source.effects
            #expect(effects[0].1["keys"]?.array == [.string(mode == "once" ? "enter" : "escape")])
            #expect(try await service.feed()["items"].array?.isEmpty == true)
        }
    }
    @Test func changedPermissionScreenAndUnrecognizedOrUnblockedDialogsDoNotExecute() async throws {
        let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: screen)
        let backend = bridge(source), item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        await source.configure(screen: screen.replacingOccurrences(of: "Run command", with: "Different command"))
        await #expect(throws: BridgeError.self) { _ = try await backend.request("feed.permission.reply", params: ["request_id": item["request_id"], "mode": .string("once")]) }
        #expect(await source.effects.isEmpty)
        await source.configure(screen: "Do you want to proceed?\n1. Yes\n2. No")
        #expect(try await backend.request("feed.list", params: [:])["items"].array?.isEmpty == true)
        await source.configure(screen: screen); await source.setAgentField("state", .string("working"))
        #expect(try await backend.request("feed.list", params: [:])["items"].array?.isEmpty == true)
    }
    @Test func decisionUnknownSurvivesRestartAndAnotherPhoneCannotRepeatIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: screen, lost: true)
        let backend = bridge(source, ledger: MutationLedger(directory: root)), item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        await #expect(throws: BridgeError.self) { _ = try await backend.request("feed.permission.reply", params: ["request_id": item["request_id"], "mode": .string("once")]) }
        let restarted = bridge(source, ledger: MutationLedger(directory: root))
        #expect(try await restarted.request("feed.list", params: [:])["items"].array?.isEmpty == true)
        #expect(await source.effects.count == 1)
    }
    @Test func permanentModesAreNotAdvertisedOrAccepted() async throws {
        let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: screen)
        let backend = bridge(source), item = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        await #expect(throws: BridgeError.self) { _ = try await backend.request("feed.permission.reply", params: ["request_id": item["request_id"], "mode": .string("always")]) }
        #expect(await source.effects.isEmpty)
    }
    /// A dialog that only waits for Enter or Escape becomes one question with those two choices.
    private let notice = "Session restored\n\nPress Enter to continue\nEsc to cancel\n"
    @Test func continueNoticeOffersContinueAndCancelAsAQuestion() async throws {
        for (choice, key) in [("继续", "enter"), ("取消", "escape")] {
            let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: notice)
            let backend = bridge(source), service = SessionService(cmux: backend, home: URL(fileURLWithPath: "/fixture"), transcriptRoots: [])
            let record = try #require(try await service.sessions().first)
            let item = try #require(try await service.feed()["items"].array?.first)
            #expect(item["kind"].string == "question")
            let questions = try #require(item["questions"].array), question = try #require(questions.first)
            let labels = (question["options"].array ?? []).compactMap(\.string) + (question["options"].array ?? []).compactMap { $0["label"].string }
            #expect(labels.contains("继续") && labels.contains("取消"))
            // The dialog names every answer it accepts, so the form must not offer a third or a way to send nothing.
            #expect(question["allow_custom"].bool == false)
            #expect(question["allow_skip"].bool == false)
            // The dialog's own words are shown, and its title is not repeated as the question.
            #expect((item["body"].string ?? "").contains("Esc to cancel"))
            #expect(question["prompt"].string != item["title"].string)
            // A permission mode is not accepted for a prompt that grants nothing.
            await #expect(throws: BridgeError.self) { _ = try await service.reply(requestID: item["request_id"].string!, body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")])) }
            #expect(await source.effects.isEmpty)
            let access = SessionAccess(clientID: "phone") { capability, workspace in #expect(capability == .feedReply); #expect(workspace == record.workspaceID) }
            _ = try await service.reply(requestID: item["request_id"].string!, body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("question"), "selections": .array([.string(choice)])]), access: access)
            let effects = await source.effects
            #expect(effects.count == 1)
            #expect(effects.first?.1["keys"]?.array == [.string(key)])
            #expect(try await service.feed()["items"].array?.isEmpty == true)
        }
    }
    @Test func aNoticeWithoutItsEscapeHintStaysUnsupported() async throws {
        // No way back: the dialog is not offered as a question with a single choice.
        for text in ["Press Enter to continue\n", "Esc to cancel\n", "Session restored\n"] {
            let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: text)
            let items = try await bridge(source).request("feed.list", params: [:])["items"].array ?? []
            #expect(items.isEmpty)
        }
        // A permission layout keeps its own card even when its footer also names Enter and Escape.
        let permissionWithFooter = "Run command\nDo you want to proceed?\n❯ 1. Yes\n2. Yes, and don't ask again\n3. No\nPress Enter to continue\nEsc to cancel\n"
        let source = TuiResourceFixture(); await source.setAgentField("state", .string("blocked")); await source.configure(screen: permissionWithFooter)
        let item = try #require(try await bridge(source).request("feed.list", params: [:])["items"].array?.first)
        #expect(item["kind"].string == "permissionRequest")
        // A choice the prompt did not offer is refused before anything is written.
        let noticeSource = TuiResourceFixture(); await noticeSource.setAgentField("state", .string("blocked")); await noticeSource.configure(screen: notice)
        let backend = bridge(noticeSource), noticeItem = try #require(try await backend.request("feed.list", params: [:])["items"].array?.first)
        await #expect(throws: BridgeError.self) { _ = try await backend.request("feed.question.reply", params: ["request_id": noticeItem["request_id"], "selections": .array([.string("not an option")])]) }
        #expect(await noticeSource.effects.isEmpty)
    }
}
