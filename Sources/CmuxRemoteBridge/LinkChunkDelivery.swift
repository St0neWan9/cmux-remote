import Foundation

/// One response being delivered in chunks, and the delivering task's wait for their acknowledgements.
struct LinkChunkDelivery {
    let count: Int
    /// Chunks handed to the link; the client may acknowledge only these.
    var sent = 0
    /// Chunks the client acknowledged, always in order.
    var acknowledged = 0
    var waiter: CheckedContinuation<Void, any Error>?
    /// Identifies the current wait, so a stale deadline cannot fail a later one.
    var token: UUID?
}
