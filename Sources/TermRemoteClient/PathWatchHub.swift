import Foundation

/// Shares one Bridge subscription per path among everyone watching it.
///
/// A link carries at most eight subscriptions. A conversation page, the session list and the off-screen followers
/// each opened their own, so the same path was subscribed several times and the duplicates filled the link. The
/// limit now counts distinct paths only.
actor PathWatchHub {
    /// Watches one path until cancelled or refused for good, calling `changed` for each invalidation.
    typealias Watch = @Sendable (_ path: String, _ changed: @escaping @Sendable () async -> Void) async -> Void
    private struct Watcher {
        var paths: Set<String>
        let changed: @Sendable () -> Void
        let finished: @Sendable () -> Void
    }
    private let watch: Watch
    private var watchers: [UUID: Watcher] = [:]
    private var subscriptions: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    init(watch: @escaping Watch) { self.watch = watch }

    /// The number of paths with a subscription, for tests.
    var subscribedPaths: Int { subscriptions.count }

    func add(_ id: UUID, paths: Set<String>, changed: @escaping @Sendable () -> Void, finished: @escaping @Sendable () -> Void) {
        watchers[id] = Watcher(paths: paths, changed: changed, finished: finished)
        for path in paths {
            if subscriptions[path] != nil {
                // The shared subscription already delivered its first invalidation; a new watcher needs its own.
                changed(); continue
            }
            let token = UUID(), watch = watch
            let task = Task { [weak self] in
                // Delivered in order, so the invalidation a refusal sends reaches watchers before they are finished.
                await watch(path) { [weak self] in await self?.deliver(path) }
                await self?.ended(path, token: token)
            }
            subscriptions[path] = (token, task)
        }
    }

    func remove(_ id: UUID) {
        guard let watcher = watchers.removeValue(forKey: id) else { return }
        for path in watcher.paths where !watchers.values.contains(where: { $0.paths.contains(path) }) {
            subscriptions.removeValue(forKey: path)?.task.cancel()
        }
    }

    private func deliver(_ path: String) {
        for watcher in watchers.values where watcher.paths.contains(path) { watcher.changed() }
    }

    /// A subscription refused for good ends its path for every watcher; a watcher with no paths left is finished.
    private func ended(_ path: String, token: UUID) {
        guard subscriptions[path]?.token == token else { return }
        subscriptions[path] = nil
        for (id, var watcher) in watchers where watcher.paths.contains(path) {
            watcher.paths.remove(path)
            if watcher.paths.isEmpty { watchers[id] = nil; watcher.finished() } else { watchers[id] = watcher }
        }
    }
}
