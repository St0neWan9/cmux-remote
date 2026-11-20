import Foundation

/// Bounds received-but-unprocessed link packets by count and bytes; the event loop admits, the consumer releases.
final class LinkInputBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let packetLimit: Int
    private let byteLimit: Int
    private var packets = 0
    private var bytes = 0
    init(packetLimit: Int = 64, byteLimit: Int = 8_388_608) { self.packetLimit = packetLimit; self.byteLimit = byteLimit }
    /// False means the consumer is too far behind; the connection closes instead of buffering without bound.
    func admit(_ count: Int) -> Bool {
        lock.withLock {
            guard packets < packetLimit, bytes + count <= byteLimit else { return false }
            packets += 1; bytes += count; return true
        }
    }
    func release(_ count: Int) { lock.withLock { packets -= 1; bytes -= count } }
}
