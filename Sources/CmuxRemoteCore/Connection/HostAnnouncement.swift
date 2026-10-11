import Foundation

/// The host signs its runtime epoch; captured HTTP proofs cannot replay across Bridge restarts.
public struct HostAnnouncement: Codable, Sendable {
    public var host: HostIdentity
    public var epoch: String
    public var version = 2
    public init(host: HostIdentity, epoch: String) { self.host = host; self.epoch = epoch }
}
