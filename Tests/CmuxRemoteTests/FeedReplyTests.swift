import Foundation
import Testing
import CmuxRemoteBridge
import CmuxRemoteCore

private actor FeedFixture: CmuxControlling {
    let item: JSONValue
    let fail: Bool
    var replies: [(String, [String: JSONValue])] = []
    init(kind: String, fail: Bool = false, source: String = "claude") {
        self.fail = fail
        item = .object(["request_id": .string("request"), "kind": .string(kind), "source": .string(source), "workspace_id": .string("workspace"), "status": .string("pending"), "questions": .array([.object(["prompt": .string("One")]), .object(["prompt": .string("Two")])])])
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        if method == "feed.list" { return .object(["items": .array([item])]) }
        replies.append((method, params))
        if fail { throw BridgeError("outcome_unknown", "Lost receipt", status: 504) }
        return .object(["delivered": .bool(true)])
    }
}
private actor WaitingFeedFixture: CmuxControlling {
    var replies = 0
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<JSONValue, any Error>?
    func finish() { continuation?.resume(returning: .object(["delivered": .bool(true)])); continuation = nil }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        if method == "feed.list" { return .object(["items": .array([.object(["request_id": .string("request"), "kind": .string("permissionRequest"), "source": .string("claude"), "workspace_id": .string("workspace"), "status": .string("pending")])])]) }
        replies += 1
        return try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started.continuation.yield(()) }
    }
}

@Suite struct FeedReplyTests {
    @Test(arguments: ["once", "always", "all", "deny"])
    func supportedClaudePermissionModesReachOnlyFixedFeedMethod(_ mode: String) async throws {
        let fixture = FeedFixture(kind: "permissionRequest")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        let body: JSONValue = .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string(mode), "command": .string("must not forward")])
        let access = SessionAccess { capability, workspace in #expect(capability == .feedReply); #expect(workspace == "workspace") }
        _ = try await service.reply(requestID: "request", body: body, access: access)
        let replies = await fixture.replies
        #expect(replies.count == 1)
        #expect(replies[0].0 == "feed.permission.reply")
        #expect(replies[0].1 == ["request_id": .string("request"), "mode": .string(mode)])
    }
    @Test(arguments: ["ultraplan", "bypassPermissions", "autoAccept", "manual", "deny"])
    func planModesAndFeedbackReachThePlanReply(_ mode: String) async throws {
        let fixture = FeedFixture(kind: "exitPlan")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("exitPlan"), "mode": .string(mode), "feedback": .string("Please keep tests")]))
        let replies = await fixture.replies
        #expect(replies[0].0 == "feed.exit_plan.reply")
        #expect(replies[0].1["feedback"] == .string("Please keep tests"))
    }
    @Test func invalidModeAndRevokedGrantNeverReachTheAgent() async throws {
        let fixture = FeedFixture(kind: "permissionRequest")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        for mode in ["manual", "shell.execute", "bypass"] {
            do { _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string(mode)])); Issue.record("Expected mode denial") }
            catch { #expect((error as? BridgeError)?.code == "invalid_input") }
        }
        do {
            _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("all")]), access: SessionAccess { _, _ in throw BridgeError("scope_denied", "Denied", status: 403) })
            Issue.record("Expected scope denial")
        } catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        #expect(await fixture.replies.isEmpty)
    }
    @Test func officialPartialAndEmptyQuestionRepliesAreAccepted() async throws {
        let fixture = FeedFixture(kind: "question")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        for answers in [[], ["First answer"]] {
            _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("question"), "selections": .array(answers.map(JSONValue.string))]))
        }
        #expect(await fixture.replies.count == 2)
    }
    @Test func nonStringAnswersAreRejectedAndSelectedLabelsStayOrdered() async throws {
        let fixture = FeedFixture(kind: "question")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        do { _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("question"), "selections": .array([.number(1)])])); Issue.record("Expected string validation") }
        catch { #expect((error as? BridgeError)?.code == "invalid_input") }
        #expect(await fixture.replies.isEmpty)
        _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("question"), "selections": .array([.string("A, B"), .string("Custom")])]))
        let replies = await fixture.replies
        #expect(replies[0].1["selections"] == .array([.string("A, B"), .string("Custom")]))
    }
    @Test func concurrentSameIdentityNeverSendsTheDecisionTwice() async throws {
        let fixture = WaitingFeedFixture()
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        let body: JSONValue = .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")])
        let first = Task { try await service.reply(requestID: "request", body: body) }
        var started = fixture.started.stream.makeAsyncIterator(); _ = await started.next()
        do { _ = try await service.reply(requestID: "request", body: body); Issue.record("Expected in-flight outcome") }
        catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        #expect(await fixture.replies == 1)
        await fixture.finish(); _ = try await first.value
        _ = try await service.reply(requestID: "request", body: body)
        #expect(await fixture.replies == 1)
    }
    @Test func successfulReceiptDeduplicatesAndRejectsChangedInput() async throws {
        let fixture = FeedFixture(kind: "permissionRequest")
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        let operation = UUID().uuidString
        let first: JSONValue = .object(["operation_id": .string(operation), "kind": .string("permissionRequest"), "mode": .string("once")])
        _ = try await service.reply(requestID: "request", body: first)
        for _ in 0..<8 { _ = try await service.reply(requestID: "request", body: first) }
        do { _ = try await service.reply(requestID: "request", body: .object(["operation_id": .string(operation), "kind": .string("permissionRequest"), "mode": .string("deny")])); Issue.record("Expected input conflict") }
        catch { #expect((error as? BridgeError)?.code == "operation_conflict") }
        #expect(await fixture.replies.count == 1)
    }
    @Test func lostFeedReceiptIsNotRetried() async {
        let fixture = FeedFixture(kind: "permissionRequest", fail: true)
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        let body: JSONValue = .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")])
        for _ in 0..<2 {
            do { _ = try await service.reply(requestID: "request", body: body); Issue.record("Expected lost receipt") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await fixture.replies.count == 1)
    }
}
