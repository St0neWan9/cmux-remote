import Foundation

/// Fans one client's link state out to every view that shows it, starting each with the current state.
///
/// The link is replaced when a Mac moves address, so the state lives here rather than on one connection.
final class LinkStateBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var current: LinkState?
    private var observers: [UUID: AsyncStream<LinkState>.Continuation] = [:]

    func report(_ state: LinkState) {
        lock.lock()
        guard current != state else { lock.unlock(); return }
        current = state; let targets = Array(observers.values)
        lock.unlock()
        for observer in targets { observer.yield(state) }
    }

    func states() -> AsyncStream<LinkState> {
        let (stream, continuation) = AsyncStream<LinkState>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        lock.lock(); observers[id] = continuation; let now = current; lock.unlock()
        if let now { continuation.yield(now) }
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        return stream
    }

    func finish() {
        lock.lock(); let targets = Array(observers.values); observers.removeAll(); lock.unlock()
        for observer in targets { observer.finish() }
    }

    private func remove(_ id: UUID) { lock.lock(); observers[id] = nil; lock.unlock() }
}
