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
}
