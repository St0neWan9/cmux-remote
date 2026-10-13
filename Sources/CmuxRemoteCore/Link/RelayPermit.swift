import Foundation

/// Public admission proof; it grants transport admission, never resource authority.
public struct RelayPermit: Codable, Sendable, Equatable {
    public let version: Int
    public let hostID: String
    public let origin: String
    public let permitID: String
    public let kind: String
    public let clientPublicKey: String?
    public let expiresAt: Int?
    public init(hostID: String, origin: String, permitID: String, kind: String, clientPublicKey: String? = nil, expiresAt: Int? = nil) {
        version = 3; self.hostID = hostID; self.origin = origin; self.permitID = permitID; self.kind = kind; self.clientPublicKey = clientPublicKey; self.expiresAt = expiresAt
    }
}
