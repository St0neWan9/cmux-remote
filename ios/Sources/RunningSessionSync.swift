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
    private var followers: [String: ConversationModel] = [:]
    /// Conversations followed while they ran, kept for the pass that reads how they ended.
    private var wasRunning: Set<String> = []
    /// The single read for each conversation that just finished.
    private var finishing: [String: Task<Void, Never>] = [:]

    /// Four at most: each follower holds one subscription of the sixteen a Bridge link allows, which still leaves
    /// the list, the feed and the open conversation their own.
    init(limit: Int = 4, interval: Duration = .seconds(8)) {
        self.limit = limit; self.interval = interval
    }

    /// The conversations being followed off screen; one now on screen follows itself and is not counted.
    var followed: Set<String> { Set(followers.filter(\.value.following).keys) }

    /// `targets` are the listed conversations, most recent first.
    func update(_ targets: [Target]) {
        let finished = targets.filter { !$0.running && wasRunning.contains($0.key) }
        for target in finished {
            wasRunning.remove(target.key); followers[target.key]?.unfollow(); followers[target.key] = nil
            let model = target.model()
            finishing[target.key] = Task { await model.syncHidden() }
        }
        let wanted = Array(targets.filter(\.running).prefix(limit))
        let keys = Set(wanted.map(\.key))
        for (key, model) in followers where !keys.contains(key) { model.unfollow(); followers[key] = nil }
        // Asked again on every update: a conversation that left the screen resumes being followed.
        for target in wanted {
            let model = followers[target.key] ?? target.model()
            followers[target.key] = model; model.follow(every: interval)
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
        for model in followers.values { model.unfollow() }
        for task in finishing.values { task.cancel() }
        followers = [:]; finishing = [:]; wasRunning = []
    }
}
