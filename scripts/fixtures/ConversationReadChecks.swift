import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

private actor HeldConversationHistory {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<ConversationSnapshot, any Error>?
    private var calls = 0
    let old: ConversationSnapshot
    let new: ConversationSnapshot
    let holdOlder: Bool
    init(old: ConversationSnapshot, new: ConversationSnapshot, holdOlder: Bool = false) { self.old = old; self.new = new; self.holdOlder = holdOlder }
    func read(_ before: Int?) async throws -> ConversationSnapshot {
        calls += 1
        if (holdOlder && before != nil) || (!holdOlder && calls == 1) {
            return try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) }
        }
        return new
    }
    func finish() { held?.resume(returning: old); held = nil }
}

/// Exercises the actual conversation model at suspended network boundaries.
struct ConversationReadChecks {
    @MainActor static func run(client: RemoteClient) async -> (count: Int, failures: [String]) {
        var failures: [String] = []; var count = 0
        func check(_ condition: Bool, _ description: String) { count += 1; if !condition { failures.append(description) } }
        let descriptor = SessionDescriptor(id: "read-races", agent: "claude", title: "Read races", cwd: nil)
        func message(_ id: String, _ seq: Int) -> ChatMessage {
            ChatMessage(id: id, seq: seq, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: id)))
        }
        let old = ConversationSnapshot(messages: [message("old", 1)], hasMore: true, generation: "old-generation", clipped: false)
        let new = ConversationSnapshot(messages: [message("new", 10)], hasMore: false, generation: "new-generation", clipped: false)
        func model(_ fixture: HeldConversationHistory) -> ConversationModel {
            ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
                readSessions: { [descriptor] }, readHistory: { try await fixture.read($0) }, readPreview: { PreviewSnapshot(text: nil, available: false) })
        }
        let overlap = HeldConversationHistory(old: old, new: new); let overlapping = model(overlap)
        let first = Task { @MainActor in await overlapping.refresh() }
        var started = overlap.started.stream.makeAsyncIterator(); _ = await started.next()
        await overlapping.refresh(); await overlap.finish(); await first.value
        check(overlapping.messages.map(\.id) == ["new"] && overlapping.historyGeneration == "new-generation" && !overlapping.hasMore, "A delayed refresh replaced the newer conversation generation")

        let cancelled = HeldConversationHistory(old: old, new: new); let cancelledModel = model(cancelled)
        let cancelledTask = Task { @MainActor in await cancelledModel.refresh() }
        var cancelledStarted = cancelled.started.stream.makeAsyncIterator(); _ = await cancelledStarted.next()
        cancelledTask.cancel(); await cancelled.finish(); await cancelledTask.value
        check(cancelledModel.messages.isEmpty && cancelledModel.historyGeneration == nil && cancelledModel.error == nil, "Cancelled conversation refresh published history")

        let olderFixture = HeldConversationHistory(old: old, new: new, holdOlder: true); let olderModel = model(olderFixture)
        await olderModel.refresh()
        let olderTask = Task { @MainActor in await olderModel.older() }
        var olderStarted = olderFixture.started.stream.makeAsyncIterator(); _ = await olderStarted.next()
        olderTask.cancel(); await olderFixture.finish(); await olderTask.value
        check(olderModel.messages.map(\.id) == ["new"], "Cancelled older-page read replaced current history")
        let sameGeneration = ConversationSnapshot(messages: [message("cancelled-page", 1)], hasMore: false, generation: "new-generation", clipped: false)
        let olderCancelled = HeldConversationHistory(old: sameGeneration, new: new, holdOlder: true); let olderCancelledModel = model(olderCancelled)
        await olderCancelledModel.refresh()
        let cancelledPageTask = Task { @MainActor in await olderCancelledModel.older() }
        var pageStarted = olderCancelled.started.stream.makeAsyncIterator(); _ = await pageStarted.next()
        cancelledPageTask.cancel(); await olderCancelled.finish(); await cancelledPageTask.value
        check(olderCancelledModel.messages.map(\.id) == ["new"], "Cancelled older-page read inserted stale messages into the active generation")
        return (count, failures)
    }
}
