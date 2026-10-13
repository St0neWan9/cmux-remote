import Foundation

/// A WebSocket ping result that settles exactly once.
///
/// `URLSessionWebSocketTask.sendPing` hands its result to a completion handler, and closing the session or
/// cancelling the task can deliver that handler alongside a cancelled waiter. Resuming a checked continuation
/// twice traps the process, so the first outcome wins and later ones are ignored.
public final class WebSocketPing: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    public init() {}

    /// Runs `send` with a handler that may be called more than once.
    public func run(_ send: (@escaping @Sendable ((any Error)?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            lock.lock(); continuation = done; lock.unlock()
            send { [self] error in settle(error) }
        }
    }

    /// Settles the ping from the socket's completion handler.
    public func settle(_ error: (any Error)?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        guard let pending else { return }
        if let error { pending.resume(throwing: error) } else { pending.resume() }
    }

    /// Settles a ping that is still waiting, so a cancelled heartbeat never leaves one suspended.
    public func cancel() { settle(CancellationError()) }

    /// Whether a ping is still waiting, for tests that must cancel one in flight.
    public var isPendingForTesting: Bool { lock.withLock { continuation != nil } }
}
