import Foundation

/// Keeps conversations that are running off screen current, in the foreground and when iOS wakes the app.
///
/// In the foreground only a few are followed at once, and each reads only after its Bridge reports a change and at most once per
/// interval, so the relay sees little more than the change notices it already carries. A conversation that just
/// stopped running is followed for one more pass, so its final answer is read too.
@MainActor final class RunningSessionSync {
    struct Target {
        let key: String
        let running: Bool
        /// Changed on its Mac since the copy on this phone was stored, e.g. a turn that ended while the app was away.
        var changedSinceStored = false
        /// Made only for a conversation that is followed, so listing one costs nothing.
        let model: @MainActor () -> ConversationModel
    }
    private let limit: Int
    private let interval: Duration
    private var followers: [String: Task<Void, Never>] = [:]
    /// Conversations followed while they ran, kept for the pass that reads how they ended.
    private var wasRunning: Set<String> = []
    /// The single read for each conversation that just finished.
    private var finishing: [String: Task<Void, Never>] = [:]

    init(limit: Int = 3, interval: Duration = .seconds(8)) {
        self.limit = limit; self.interval = interval
    }

    var followed: Set<String> { Set(followers.keys) }

    /// `targets` are the listed conversations, most recent first.
    func update(_ targets: [Target]) {
        let finished = targets.filter { !$0.running && wasRunning.contains($0.key) }
        for target in finished {
            wasRunning.remove(target.key); followers[target.key]?.cancel(); followers[target.key] = nil
            let model = target.model()
            finishing[target.key] = Task { await model.syncHidden() }
        }
        let wanted = Array(targets.filter(\.running).prefix(limit))
        let keys = Set(wanted.map(\.key))
        for (key, follower) in followers where !keys.contains(key) { follower.cancel(); followers[key] = nil }
        for target in wanted where followers[target.key] == nil {
            let model = target.model(), interval = interval
            followers[target.key] = Task { await model.followHidden(every: interval) }
        }
        wasRunning.formUnion(keys)
    }

    /// One pass for a background wake: reads, at once, the conversations that are running or changed since they
    /// were stored, most recent first and within the same limit. Nothing is followed afterwards.
    func pass(_ targets: [Target]) async -> Int {
        let wanted = Array(targets.filter { $0.running || $0.changedSinceStored }.prefix(limit)).map { $0.model() }
        await withTaskGroup(of: Void.self) { group in
            for model in wanted { group.addTask { await model.syncHidden() } }
        }
        return wanted.count
    }

    func stop() {
        for task in Array(followers.values) + Array(finishing.values) { task.cancel() }
        followers = [:]; finishing = [:]; wasRunning = []
    }
}
