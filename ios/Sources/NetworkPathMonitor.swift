import Foundation
import Network

/// Reports when the phone's network comes back, so links can be dialed again without waiting for a timeout.
struct NetworkPathMonitor: Sendable {
    /// One `true` each time a usable path appears after none, and `false` when it goes away.
    func availability() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "cmux-remote.network-path")
        let last = LastValue()
        monitor.pathUpdateHandler = { path in
            let usable = path.status == .satisfied
            if last.swap(usable) != usable { continuation.yield(usable) }
        }
        continuation.onTermination = { _ in monitor.cancel() }
        monitor.start(queue: queue)
        return stream
    }
}

/// The previous path reading, touched only on the monitor's serial queue.
private final class LastValue: @unchecked Sendable {
    private var value: Bool?
    func swap(_ next: Bool) -> Bool? { defer { value = next }; return value }
}
