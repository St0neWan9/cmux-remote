import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

private actor HeldConversationHistory {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<ConversationSnapshot, any Error>?
    private var calls = 0
    private(set) var cancellationObserved = false
    let old: ConversationSnapshot
    let new: ConversationSnapshot
    let holdOlder: Bool
    init(old: ConversationSnapshot, new: ConversationSnapshot, holdOlder: Bool = false) { self.old = old; self.new = new; self.holdOlder = holdOlder }
    func read(_ before: Int?) async throws -> ConversationSnapshot {
        calls += 1
        if (holdOlder && before != nil) || (!holdOlder && calls == 1) {
            let result = try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) }
            cancellationObserved = Task.isCancelled
            return result
        }
        return new
    }
    func finish() { held?.resume(returning: old); held = nil }
}

private actor HeldConversationPreview {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<PreviewSnapshot, any Error>?
    private var calls = 0
    func read() async throws -> PreviewSnapshot {
        calls += 1
        if calls > 1 { return PreviewSnapshot(text: "new preview", available: true) }
        return try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) }
    }
    func finish() { held?.resume(returning: PreviewSnapshot(text: "old preview", available: true)); held = nil }
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
        check(await cancelled.cancellationObserved, "Cancelling the calling task did not propagate to the owned history read")
        let suspended = HeldConversationHistory(old: old, new: new); let suspendedModel = model(suspended)
        let suspendedTask = Task { @MainActor in await suspendedModel.refresh() }
        var suspendStarted = suspended.started.stream.makeAsyncIterator(); _ = await suspendStarted.next()
        suspendedModel.suspendReads(); await suspended.finish(); await suspendedTask.value
        await suspendedModel.refresh()
        let suspendedCancelled = await suspended.cancellationObserved
        check(suspendedModel.messages.isEmpty && suspendedCancelled, "Suspending the conversation kept reading or published a stale completion")
        suspendedModel.resumeReads(); await suspendedModel.refresh()
        check(suspendedModel.messages.map(\.id) == ["new"], "Foreground resume failed to restore current authorized history")
        let previewFixture = HeldConversationPreview()
        let previewModel = ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
            readSessions: { [descriptor] }, readHistory: { _ in new }, readPreview: { try await previewFixture.read() })
        let stalePreview = Task { @MainActor in await previewModel.refresh() }
        var previewStarted = previewFixture.started.stream.makeAsyncIterator(); _ = await previewStarted.next()
        await previewModel.refresh(); await previewFixture.finish(); await stalePreview.value
        check(previewModel.preview == "new preview", "A delayed live preview replaced the newer committed snapshot")
        let projectFixture = DeferredReadChecksProject()
        let project = ProjectModel(read: { _, _ in try await projectFixture.read() }, list: { [] })
        let projectTask = Task { @MainActor in await project.load(.file) }
        var projectStarted = projectFixture.started.stream.makeAsyncIterator(); _ = await projectStarted.next()
        project.suspendReads(); await projectFixture.finish(); await projectTask.value
        check(project.content.isEmpty && !project.busy, "A backgrounded project page published a late file read")
        let feedFixture = DeferredReadChecksFeed()
        let feed = FeedModel(fetch: { try await feedFixture.read() }, send: { _, _ in throw URLError(.badServerResponse) })
        let feedTask = Task { @MainActor in await feed.refresh() }
        var feedStarted = feedFixture.started.stream.makeAsyncIterator(); _ = await feedStarted.next()
        feed.suspendReads(); await feedFixture.finish(); await feedTask.value
        check(feed.items.isEmpty && !feed.loading, "A backgrounded Feed page published a late snapshot")
        let slowPage = HeldConversationHistory(old: sameGeneration, new: new, holdOlder: true)
        let paging = model(slowPage); await paging.refresh()
        let slowPageTask = Task { @MainActor in await paging.older() }
        var slowPageStarted = slowPage.started.stream.makeAsyncIterator(); _ = await slowPageStarted.next()
        await paging.refresh(); await slowPage.finish(); await slowPageTask.value
        check(paging.messages.map(\.id) == ["cancelled-page", "new"], "A periodic refresh cancelled an older page from the unchanged transcript generation")
        return (count, failures)
    }
}

private actor DeferredReadChecksProject {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<TextFileSnapshot, any Error>?
    func read() async throws -> TextFileSnapshot { try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) } }
    func finish() { held?.resume(returning: TextFileSnapshot(path: "old", text: "late", truncated: false)); held = nil }
}
private actor DeferredReadChecksFeed {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<[JSONValue], any Error>?
    func read() async throws -> [JSONValue] { try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) } }
    func finish() { held?.resume(returning: [.object(["request_id": .string("late")])]); held = nil }
}
