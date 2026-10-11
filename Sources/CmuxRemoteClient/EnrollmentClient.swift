import Foundation
import CmuxRemoteCore

/// One independently identified client requesting bounded owner-approved enrollment.
public final class EnrollmentClient: Sendable {
    public let bootstrap: SignedValue<EnrollmentBootstrap>
    public let request: SignedValue<EnrollmentRequest>
    private let endpoint: BridgeEndpoint
    private let privateKey: Data
    private let transport: PinnedTransport
    public init(bootstrap: SignedValue<EnrollmentBootstrap>, privateKey: Data, name: String, kind: String, endpoint: BridgeEndpoint? = nil, now: Int = Int(Date().timeIntervalSince1970)) throws {
        try EnrollmentLinkCodec().validate(bootstrap, now: now)
        self.bootstrap = bootstrap; self.privateKey = privateKey; self.endpoint = endpoint ?? bootstrap.value.endpoint
        let crypto = IdentityCryptography(); let publicKey = try crypto.publicKey(privateKey: privateKey)
        let scope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: ClientCapability.allCases)
        let value = EnrollmentRequest(hostID: bootstrap.value.host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: try crypto.identityID(publicKey: publicKey), clientPublicKey: publicKey, clientName: name, clientKind: kind, nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        request = try crypto.sign(value, domain: "enrollment-request", privateKey: privateKey)
        transport = PinnedTransport(pairing: try PairingConfiguration(host: self.endpoint.host, port: self.endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: bootstrap.value.host.certificateSHA256))
    }
    public func submit() async throws -> EnrollmentStatus { try await exchange("request") }
    public func status() async throws -> EnrollmentStatus { try await exchange("status") }
    public func cancel() async throws { _ = try await exchange("cancel") }
    public func close() { transport.close() }
    public func connection(from status: EnrollmentStatus) throws -> AuthorizedConnection {
        try validate(status)
        guard status.state == "approved", let grant = status.grant else { throw BridgeError("enrollment_pending", "Approve this device on the Mac first.") }
        try IdentityCryptography().verify(grant, domain: "grant", publicKey: bootstrap.value.host.publicKey)
        guard grant.value.requestID == request.value.requestID, grant.value.nonce == request.value.nonce,
              Set(grant.value.scope.workspaces).isSubset(of: Set(request.value.scope.workspaces)), Set(grant.value.scope.capabilities).isSubset(of: Set(request.value.scope.capabilities)) else { throw BridgeError("invalid_grant", "Approval does not match the requested scope.") }
        let connection = AuthorizedConnection(host: bootstrap.value.host, endpoint: endpoint, privateKey: privateKey, grant: grant)
        try connection.validate(); return connection
    }
    private func exchange(_ verb: String) async throws -> EnrollmentStatus {
        let signed = try await transport.request("/v2/enrollment/" + verb, method: "POST", body: JSONEncoder().encode(request), as: SignedValue<EnrollmentStatus>.self)
        try IdentityCryptography().verify(signed, domain: "enrollment-status", publicKey: bootstrap.value.host.publicKey)
        try validate(signed.value); return signed.value
    }
    private func validate(_ status: EnrollmentStatus) throws {
        guard status.hostID == request.value.hostID, status.clientID == request.value.clientID, status.requestID == request.value.requestID, status.nonce == request.value.nonce else { throw BridgeError("invalid_grant", "The enrollment response belongs to another host or device.") }
    }
}
