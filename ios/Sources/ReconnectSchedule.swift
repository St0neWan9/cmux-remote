import Foundation
import CmuxRemoteClient

/// Paces automatic redials of lost Macs: at once when a working link drops, then after growing pauses.
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
    /// Automatic retries since the links last worked; it picks the next pause.
    private(set) var attempt = 0
    /// Macs whose working link dropped since the last step, in the order they dropped.
    private var dropped: [String] = []
    private var nap: Task<Void, Never>?
    init(pauses: [Duration] = [3, 5, 10, 20, 30].map { .seconds($0) }) {
        precondition(!pauses.isEmpty, "A schedule needs at least one pause")
        self.pauses = pauses
    }
    /// The wait before the next check: the first entry before any retry, then one step longer per retry.
    var pause: Duration { pauses[min(attempt, pauses.count - 1)] }

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
    func step(states: [String: LinkState], waited full: Bool) -> Step {
        let lost = dropped.filter { states[$0] == .disconnected }
        dropped.removeAll()
        if !lost.isEmpty { attempt = 1; return .redialDropped(lost) }
        guard full else { return .idle }
        let waited = pause
        guard !states.values.contains(.connecting), states.values.contains(.disconnected) else { attempt = 0; return .idle }
        attempt += 1
        return .retryLost(attempt: attempt, waited: waited)
    }
}
