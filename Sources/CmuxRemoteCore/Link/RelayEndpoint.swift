import Foundation

/// A signed relay hint travels with bootstrap or a saved device connection.
public struct RelayEndpoint: Codable, Sendable, Equatable {
    public let origin: String
    public let admission: SignedValue<RelayPermit>
    public init(origin: String, admission: SignedValue<RelayPermit>) { self.origin = origin; self.admission = admission }
    public func validate(host: HostIdentity, clientPublicKey: String? = nil, now: Int = Int(Date().timeIntervalSince1970)) throws {
        let crypto = IdentityCryptography(); try crypto.verify(admission, domain: "relay3-permit", publicKey: host.publicKey)
        let permit = admission.value
        guard permit.version == 3, permit.hostID == host.id, try RelayOrigin(origin).value == origin, permit.origin == origin,
              !permit.permitID.isEmpty, permit.permitID.utf8.count <= 128 else { throw BridgeError("invalid_identity", "Invalid relay admission identity.") }
        if permit.kind == "enrollment" {
            guard clientPublicKey == nil, permit.clientPublicKey == nil, let expiry = permit.expiresAt, expiry > now, expiry - now <= 600 else { throw BridgeError("enrollment_expired", "The relay enrollment window expired.") }
        } else {
            guard permit.kind == "approved", permit.expiresAt == nil, let identity = permit.clientPublicKey,
                  clientPublicKey == nil || identity == clientPublicKey else { throw BridgeError("invalid_identity", "The relay permit belongs to another device.") }
            _ = try crypto.identityID(publicKey: identity)
        }
    }
}
