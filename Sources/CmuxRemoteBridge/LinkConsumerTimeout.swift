import Foundation

/// A response the consumer stopped acknowledging. It ends that response only: the channel keeps its link, its
/// other requests and its subscriptions, so one stalled read cannot take down everything the phone is doing.
struct LinkConsumerTimeout: Error, Sendable {
    /// Chunks handed to the link.
    let sent: Int
    /// Chunks the client acknowledged before it went quiet.
    let acknowledged: Int
}
