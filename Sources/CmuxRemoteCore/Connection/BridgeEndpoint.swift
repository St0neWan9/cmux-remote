import Foundation

/// An endpoint is only a reachability hint; the saved host identity supplies trust.
public struct BridgeEndpoint: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var relay: RelayEndpoint?
    public init(host: String, port: Int, relay: RelayEndpoint? = nil) { self.host = host; self.port = port; self.relay = relay }
    public func validate() throws {
        if let relay { _ = try RelayOrigin(relay.origin) }
        _ = try PairingConfiguration(host: host, port: port, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64))
    }
}
