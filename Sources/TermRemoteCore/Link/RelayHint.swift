import Foundation

/// A host-signed per-device reachability update, bound to the current Bridge epoch.
public struct RelayHint: Codable, Sendable {
    public let hostID: String
    public let clientID: String
    public let epoch: String
    public let relay: RelayEndpoint?
    public init(hostID: String, clientID: String, epoch: String, relay: RelayEndpoint?) { self.hostID = hostID; self.clientID = clientID; self.epoch = epoch; self.relay = relay }
}
