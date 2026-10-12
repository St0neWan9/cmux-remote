import Foundation

/// Saved host trust, device private identity and the host-signed per-client grant.
public struct AuthorizedConnection: Codable, Sendable {
    public var host: HostIdentity
    public var endpoint: BridgeEndpoint
    public var privateKey: Data
    public var grant: SignedValue<EnrollmentGrant>
    public init(host: HostIdentity, endpoint: BridgeEndpoint, privateKey: Data, grant: SignedValue<EnrollmentGrant>) {
        self.host = host; self.endpoint = endpoint; self.privateKey = privateKey; self.grant = grant
    }
    public func validate() throws {
        let crypto = IdentityCryptography(); try endpoint.validate(); try crypto.validate(host)
        try crypto.verify(grant, domain: "grant", publicKey: host.publicKey)
        guard grant.value.hostID == host.id,
              try crypto.identityID(publicKey: crypto.publicKey(privateKey: privateKey)) == grant.value.clientID else { throw BridgeError("invalid_identity", "Saved host and device identities do not match.") }
        try grant.value.scope.validate()
    }
    public func relocated(to endpoint: BridgeEndpoint, advertisedHost: HostIdentity) throws -> AuthorizedConnection {
        try endpoint.validate()
        guard advertisedHost.id == host.id, advertisedHost.publicKey == host.publicKey, advertisedHost.certificateSHA256 == host.certificateSHA256 else { throw BridgeError("host_changed", "The saved host identity or certificate changed. Pair again explicitly.") }
        var value = self; value.endpoint = endpoint; return value
    }
}
