import Foundation

/// An endpoint is only a reachability hint; the saved host identity supplies trust.
public struct BridgeEndpoint: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public init(host: String, port: Int) { self.host = host; self.port = port }
    public func validate() throws {
        _ = try PairingConfiguration(host: host, port: port, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64))
    }
}
