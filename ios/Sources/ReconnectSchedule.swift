import Foundation
import CmuxRemoteClient

/// Paces automatic redials of lost Macs: at once when a working link drops, then after growing pauses.
///
/// The pause doubles from 2 seconds up to 32 and then stays there, so a Mac that comes back is noticed within
/// half a minute while the app is open. After the first few retries the schedule turns quiet: the pages stop
/// showing the dial, since a bar that keeps turning reads as broken.
///
/// Only a link that was connected and then reported down wakes the retry early: that is the network taking it,
/// since closing a Mac's link reports nothing and a link kept for an in-flight write never goes down. A dial that
/// fails, and a Mac that stays down, wait out the next pause instead, so a dead path is not dialed in a loop.
@MainActor
final class ReconnectSchedule {
    enum Step: Equatable, Sendable {
        case idle
        /// Dial these Macs again now: their working links just dropped.
        case redialDropped([String])
        /// Dial every lost Mac again; `attempt` counts automatic retries since the links last worked.
        case retryLost(attempt: Int, waited: Duration)
    }
    private let pauses: [Duration]
    /// How many automatic retries are shown on the pages; later ones run in the background.
    private let visibleAttempts: Int
    /// Automatic retries since the links last worked; it picks the next pause.
    private(set) var attempt = 0
    /// Macs whose working link dropped since the last step, in the order they dropped.
    private var dropped: [String] = []
    private var nap: Task<Void, Never>?
    /// A lost Mac is retried every half minute at most: these retries only run while the app is open, and waiting
    /// minutes to notice the Mac is back is what "it never connects" feels like.
    init(pauses: [Duration] = [2, 4, 8, 16, 32].map { .seconds($0) }, visibleAttempts: Int = 3) {
        precondition(!pauses.isEmpty, "A schedule needs at least one pause")
        precondition(visibleAttempts >= 0)
        self.pauses = pauses
        self.visibleAttempts = visibleAttempts
    }
    /// The wait before the next check: the first entry before any retry, then one step longer per retry, and the
    /// last entry from then on.
    var pause: Duration { pauses[min(attempt, pauses.count - 1)] }
    /// Whether retries now run without the pages showing them.
    var quiet: Bool { attempt > visibleAttempts }
    /// Starts the backoff over, shown again, after a person asked for a retry or the network path changed.
    func rearm() { attempt = 0 }

    /// A Mac's link reported `next` after `previous`. A drop from connected cuts the current pause short.
    func observe(host: String, from previous: LinkState?, to next: LinkState) {
        guard previous == .connected, next == .disconnected else { return }
        if !dropped.contains(host) { dropped.append(host) }
        nap?.cancel()
    }

    /// Waits out the current pause, or less when a working link drops meanwhile or the caller is cancelled.
    /// Returns whether the whole pause passed.
    func wait() async -> Bool {
        guard dropped.isEmpty else { return false }
        let pause = pause
        let nap = Task { _ = try? await Task.sleep(for: pause) }
        self.nap = nap
        await withTaskCancellationHandler { await nap.value } onCancel: { nap.cancel() }
        if self.nap == nap { self.nap = nil }
        return !nap.isCancelled
    }

    /// What to dial after `wait()`, given each current Mac's link state.
    ///
    /// A dropped Mac that is already dialing again is left alone, so one drop never starts a second dial.
    /// A Mac that stays down is retried after every pause, for as long as the app is open.
    func step(states: [String: LinkState], waited full: Bool) -> Step {
        let lost = dropped.filter { states[$0] == .disconnected }
        dropped.removeAll()
        if !lost.isEmpty { attempt = 1; return .redialDropped(lost) }
        guard full else { return .idle }
        let waited = pause
        // A dial already under way is not a recovery: resetting the backoff whenever it happened would keep a
        // dead path at the shortest pause while a retry's own dial is in flight.
        guard !states.values.contains(.connecting) else { return .idle }
        guard states.values.contains(.disconnected) else { attempt = 0; return .idle }
        attempt += 1
        return .retryLost(attempt: attempt, waited: waited)
    }
}
