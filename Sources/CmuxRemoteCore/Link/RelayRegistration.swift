import Foundation

/// Bridge key possession is required in addition to the deployment registration secret.
public struct RelayRegistration: Codable, Sendable {
    public let version: Int
    public let hostID: String
    public let hostPublicKey: String
    public let origin: String
    public let nonce: String
    public let timestamp: Int
    public init(hostID: String, hostPublicKey: String, origin: String, nonce: String = UUID().uuidString, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        version = 3; self.hostID = hostID; self.hostPublicKey = hostPublicKey; self.origin = origin; self.nonce = nonce; self.timestamp = timestamp
    }
}
