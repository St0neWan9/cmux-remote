import Foundation

/// A client's fresh identity-certified agreement key, bound to one intended host.
public struct LinkProposal: Codable, Sendable {
    public var version: Int = 3
    public let hostID: String
    public let clientPublicKey: String
    public let agreementKey: Data
    public let nonce: String
    public let timestamp: Int
    public init(hostID: String, clientPublicKey: String, agreementKey: Data, nonce: String = UUID().uuidString, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        self.hostID = hostID; self.clientPublicKey = clientPublicKey; self.agreementKey = agreementKey; self.nonce = nonce; self.timestamp = timestamp
    }
    public func validate(hostID: String, now: Int) throws {
        guard version == 3, self.hostID == hostID, UUID(uuidString: nonce) != nil,
              timestamp >= now - 60, timestamp <= now + 60, agreementKey.count == 65 else { throw BridgeError("invalid_identity", "Invalid link identity.", status: 401) }
        _ = try IdentityCryptography().identityID(publicKey: clientPublicKey)
    }
}
