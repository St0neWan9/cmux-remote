import Foundation

/// Each connection proves device key possession and binds one exact relay permit.
public struct RelayJoin: Codable, Sendable {
    public let version: Int
    public let hostID: String
    public let clientPublicKey: String
    public let permitDigest: String
    public let nonce: String
    public let timestamp: Int
    public init(hostID: String, clientPublicKey: String, permitDigest: String, nonce: String = UUID().uuidString, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        version = 3; self.hostID = hostID; self.clientPublicKey = clientPublicKey; self.permitDigest = permitDigest; self.nonce = nonce; self.timestamp = timestamp
    }
}
