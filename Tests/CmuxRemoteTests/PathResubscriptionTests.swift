import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

/// A subscription never dials an unreachable Mac on its own: it waits for the link the reconnect schedule owns.
@Suite struct PathResubscriptionTests {
    actor Recorder {
        var subscribes = 0, changes = 0, pauses: [Duration] = []
        var down = true
        var gate: CheckedContinuation<Void, Never>?
        var waiting = false
        func subscribed() { subscribes += 1 }
        func changed() { changes += 1 }
        func paused(_ duration: Duration) { pauses.append(duration) }
        func setDown(_ value: Bool) { down = value }
        func waitForLink() async { waiting = true; await withCheckedContinuation { gate = $0 } }
        func linkCameBack() { down = false; waiting = false; gate?.resume(); gate = nil }
    }
    /// Thread-safe snapshot of `Recorder.down` for the synchronous `linkDown` probe.
    final class Flag: @unchecked Sendable {
        private let lock = NSLock(); private var value: Bool
        init(_ value: Bool) { self.value = value }
        var get: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ next: Bool) { lock.lock(); value = next; lock.unlock() }
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

    @Test func aDownLinkIsNeitherRedialedNorReadUntilItComesBack() async {
        let recorder = Recorder(), down = Flag(true)
        // Every subscribe fails while the link is down, as a dial to an unreachable Mac does; once it is up the
        // subscription holds and delivers its first invalidation.
        let loop = PathResubscription(
            subscribe: { _ in
                await recorder.subscribed()
                if down.get { throw URLError(.cannotConnectToHost) }
                let (stream, continuation) = AsyncThrowingStream<LinkFrame, any Error>.makeStream()
                continuation.yield(LinkFrame(kind: "event", id: "e"))
                return stream
            },
            linkDown: { down.get }, linkUp: { await recorder.waitForLink() },
            pause: { await recorder.paused($0) })
        let task = Task { await loop.run("/v1/sessions") { await recorder.changed() } }
        await settle()
        // One failed subscribe, then it waits: no timer, no second dial, no read that would dial again.
        #expect(await recorder.subscribes == 1)
        #expect(await recorder.changes == 0)
        #expect(await recorder.pauses.isEmpty)
        #expect(await recorder.waiting)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.subscribes == 1, "A subscription redialed a link that was down")

        // The schedule, a person or the network brought the link back: subscribe once and read.
        down.set(false); await recorder.linkCameBack(); await settle()
        #expect(await recorder.subscribes == 2)
        #expect(await recorder.changes == 2, "Expected one read on return and one for the first invalidation")
        task.cancel(); await settle()
    }

    @Test func aFailureOnAWorkingLinkBacksOffAndRetries() async {
        let recorder = Recorder()
        let loop = PathResubscription(
            subscribe: { _ in await recorder.subscribed(); throw BridgeError("internal", "Bridge hiccup", status: 500) },
            linkDown: { false }, linkUp: { Issue.record("A working link was waited on") },
            pause: { duration in await recorder.paused(duration); if await recorder.pauses.count >= 3 { throw CancellationError() } })
        await loop.run("/v1/feed") { await recorder.changed() }
        #expect(await recorder.subscribes == 3)
        #expect(await recorder.changes == 3)
        #expect(await recorder.pauses == [.seconds(2), .seconds(4), .seconds(8)])
    }

    @Test func aRefusalForGoodStopsWithoutWaiting() async {
        let recorder = Recorder()
        let loop = PathResubscription(
            subscribe: { _ in await recorder.subscribed(); throw BridgeError("scope_denied", "No access", status: 403) },
            linkDown: { true }, linkUp: { Issue.record("A refused subscription waited for the link") },
            pause: { await recorder.paused($0) })
        await loop.run("/v1/feed") { await recorder.changed() }
        #expect(await recorder.subscribes == 1)
        #expect(await recorder.changes == 1)
        #expect(await recorder.pauses.isEmpty)
    }
}
