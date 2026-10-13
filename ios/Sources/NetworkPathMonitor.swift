import Foundation
import Network

/// Reports when the phone's network comes back or moves, so links can be dialed again without waiting for a timeout.
struct NetworkPathMonitor: Sendable {
    /// `true` each time a usable path appears or switches interface (Wi-Fi to cellular), `false` when none is left.
    func availability() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "cmux-remote.network-path")
        let last = LastPath()
        monitor.pathUpdateHandler = { path in
            let usable = path.status == .satisfied
            let signature = usable ? path.availableInterfaces.map(\.name).joined(separator: ",") : ""
            if last.changed(to: signature) { continuation.yield(usable) }
        }
        continuation.onTermination = { _ in monitor.cancel() }
        monitor.start(queue: queue)
        return stream
    }
}

/// The previous path signature, touched only on the monitor's serial queue; the first reading is the baseline.
private final class LastPath: @unchecked Sendable {
    private var value: String?
    func changed(to next: String) -> Bool {
        defer { value = next }
        guard let value else { return false }
        return value != next
    }
}
