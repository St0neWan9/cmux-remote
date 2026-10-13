import Foundation
import CmuxRemoteCore

/// Coalesces ordered keystroke bytes while a bounded remote write is in flight.
final class TerminalInputBuffer: @unchecked Sendable {
    let notifications: AsyncThrowingStream<Void, any Error>
    private let continuation: AsyncThrowingStream<Void, any Error>.Continuation
    private let lock = NSLock()
    private let maximumBytes: Int
    private var bytes = Data()
    private var failure: (any Error)?
    private var closed = false

    init(maximumBytes: Int = 16_380) {
        precondition((1...16_384).contains(maximumBytes))
        self.maximumBytes = maximumBytes
        let events = AsyncThrowingStream<Void, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        notifications = events.stream; continuation = events.continuation
    }
    func append(_ value: Data) throws {
        lock.lock()
        if let failure { lock.unlock(); throw failure }
        if closed { lock.unlock(); return }
        guard value.count <= maximumBytes - bytes.count else {
            let error = BridgeError("input_queue_full", "Viewer input exceeded the byte limit; it was not retried.")
            failure = error; closed = true; bytes.removeAll()
            lock.unlock(); continuation.finish(throwing: error); throw error
        }
        bytes.append(value)
        lock.unlock()
        // Wakeups may coalesce; all input bytes remain ordered under the lock.
        continuation.yield(())
    }
    func take() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        let value = bytes; bytes.removeAll(keepingCapacity: true)
        return value
    }
    func wake() { continuation.yield(()) }
    func finish(throwing error: (any Error)? = nil) {
        lock.lock()
        closed = true
        if let error { failure = error; bytes.removeAll() }
        lock.unlock()
        continuation.finish(throwing: error)
    }
}
