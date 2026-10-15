import Foundation
import CmuxRemoteCore

/// One independently identified client requesting bounded owner-approved enrollment.
public final class EnrollmentClient: DeviceEnrolling {
    public let bootstrap: SignedValue<EnrollmentBootstrap>
    public let request: SignedValue<EnrollmentRequest>
    private let endpoint: BridgeEndpoint
    private let privateKey: Data
    private let transport: any ResourceTransport
    /// What the iPhone asks for. A Bridge older than session starting cannot decode `conversationStart`.
    public static let phoneCapabilities: [ClientCapability] = [.workspaceRead, .conversationRead, .projectRead, .conversationControl, .feedRead, .feedReply, .conversationStart]
    /// The request an older Bridge accepts.
    public static let previousPhoneCapabilities: [ClientCapability] = [.workspaceRead, .conversationRead, .projectRead, .conversationControl, .feedRead, .feedReply]
    public convenience init(bootstrap: SignedValue<EnrollmentBootstrap>, privateKey: Data, name: String, kind: String, capabilities: [ClientCapability] = [.workspaceRead, .conversationRead, .projectRead, .conversationControl, .feedRead, .feedReply], endpoint: BridgeEndpoint? = nil, now: Int = Int(Date().timeIntervalSince1970)) throws {
        try self.init(bootstrap: bootstrap, privateKey: privateKey, name: name, kind: kind, capabilities: capabilities, endpoint: endpoint, now: now, relayDial: { LinkSocket(url: $0, headers: $1, timeout: 15) })
    }
    init(bootstrap: SignedValue<EnrollmentBootstrap>, privateKey: Data, name: String, kind: String, capabilities: [ClientCapability] = [.workspaceRead, .conversationRead, .projectRead, .conversationControl, .feedRead, .feedReply], endpoint: BridgeEndpoint? = nil, now: Int = Int(Date().timeIntervalSince1970), relayDial: @escaping @Sendable (URL, [String: String]) -> LinkSocket) throws {
        try EnrollmentLinkCodec().validate(bootstrap, now: now)
        self.bootstrap = bootstrap; self.privateKey = privateKey; self.endpoint = endpoint ?? bootstrap.value.endpoint
        let crypto = IdentityCryptography(); let publicKey = try crypto.publicKey(privateKey: privateKey)
        let scope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: capabilities)
        let value = EnrollmentRequest(hostID: bootstrap.value.host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: try crypto.identityID(publicKey: publicKey), clientPublicKey: publicKey, clientName: name, clientKind: kind, nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        request = try crypto.sign(value, domain: "enrollment-request", privateKey: privateKey)
        transport = WebSocketTransport(host: bootstrap.value.host, key: privateKey, endpoint: self.endpoint, relayDial: relayDial)
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
        var savedEndpoint = endpoint
        savedEndpoint.relay = status.relay
        let connection = AuthorizedConnection(host: bootstrap.value.host, endpoint: savedEndpoint, privateKey: privateKey, grant: grant)
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
