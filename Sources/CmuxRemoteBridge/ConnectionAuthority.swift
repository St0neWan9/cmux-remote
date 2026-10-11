import Foundation
import CmuxRemoteCore

/// Serializes enrollment, owner decisions, scoped authorization and revocation.
public actor ConnectionAuthority {
    private struct Pending: Sendable {
        var request: SignedValue<EnrollmentRequest>
        var state: String = "pending"
        var grant: SignedValue<EnrollmentGrant>?
    }
    public nonisolated let host: HostIdentity
    public nonisolated let epoch = UUID().uuidString
    private let privateKey: Data
    private let file: URL
    private let now: @Sendable () -> Int
    private let crypto = IdentityCryptography()
    private var clients: [String: EnrolledClient]
    private var pending: [String: Pending] = [:]
    private var window: EnrollmentBootstrap?
    private var usedNonces: [String: Int] = [:]

    public init(host: HostIdentity, privateKey: Data, registryFile: URL, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) throws {
        self.host = host; self.privateKey = privateKey; self.file = registryFile; self.now = now
        try IdentityCryptography().validate(host)
        guard try IdentityCryptography().publicKey(privateKey: privateKey) == host.publicKey else { throw BridgeError("invalid_identity", "The host key does not match its identity.") }
        if FileManager.default.fileExists(atPath: registryFile.path) {
            let data = try Data(contentsOf: registryFile); guard data.count <= 1_048_576 else { throw BridgeError("registry_invalid", "The device registry exceeds the limit.") }
            let records = try JSONDecoder().decode([EnrolledClient].self, from: data)
            guard Set(records.map(\.id)).count == records.count else { throw BridgeError("registry_invalid", "Duplicate device identities in registry.") }
            for record in records {
                guard try IdentityCryptography().identityID(publicKey: record.publicKey) == record.id, record.grant.value.clientID == record.id, record.grant.value.hostID == host.id, record.scope == record.grant.value.scope else { throw BridgeError("registry_invalid", "The device registry has inconsistent identities.") }
                try record.scope.validate(); try IdentityCryptography().verify(record.grant, domain: "grant", publicKey: host.publicKey)
            }
            self.clients = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        } else { clients = [:] }
    }
    public func announcement() throws -> SignedValue<HostAnnouncement> { try crypto.sign(HostAnnouncement(host: host, epoch: epoch), domain: "host", privateKey: privateKey) }
    public func open(endpoint: BridgeEndpoint, workspaces: [String], seconds: Int = 300) throws -> SignedValue<EnrollmentBootstrap> {
        try endpoint.validate(); try ClientScope(workspaces: workspaces, capabilities: [.workspaceRead]).validate(); guard (30...600).contains(seconds) else { throw BridgeError("invalid_input", "Enrollment lasts between 30 and 600 seconds.") }
        // A new window cancels all still-pending requests from the old window.
        for id in pending.keys where pending[id]?.state == "pending" { pending[id]?.state = "cancelled" }
        window = EnrollmentBootstrap(host: host, endpoint: endpoint, workspaces: workspaces.map { $0.lowercased() }.sorted(), windowID: UUID().uuidString, expiresAt: now() + seconds)
        return try bootstrap()
    }
    public func closeEnrollment() {
        window = nil
        for id in pending.keys where pending[id]?.state == "pending" { pending[id]?.state = "cancelled" }
    }
    public func bootstrap() throws -> SignedValue<EnrollmentBootstrap> {
        guard let window, window.expiresAt > now() else { throw BridgeError("enrollment_closed", "Open enrollment on the Mac before adding a device.", status: 403) }
        return try crypto.sign(window, domain: "bootstrap", privateKey: privateKey)
    }
    public func submit(_ signed: SignedValue<EnrollmentRequest>) throws -> SignedValue<EnrollmentStatus> {
        try verifyRequest(signed)
        let request = signed.value
        if let previous = pending[request.requestID] {
            guard previous.request.value == request else { throw BridgeError("request_conflict", "This enrollment identity already belongs to another request.", status: 409) }
            return try status(signed)
        }
        guard let window, request.windowID == window.windowID, window.expiresAt > now(), request.expiresAt <= window.expiresAt, Set(request.scope.workspaces).isSubset(of: Set(window.workspaces)) else { throw BridgeError("enrollment_closed", "This enrollment window is no longer open.", status: 403) }
        pending = pending.filter { $0.value.request.value.expiresAt > now() }
        guard pending.count < 32 else { throw BridgeError("enrollment_capacity", "Too many device requests. Try later.", status: 429) }
        pending[request.requestID] = Pending(request: signed)
        return try status(signed)
    }
    public func status(_ signed: SignedValue<EnrollmentRequest>) throws -> SignedValue<EnrollmentStatus> {
        try verifyRequest(signed, allowExpired: true)
        guard let entry = pending[signed.value.requestID], entry.request.value == signed.value else { throw BridgeError("request_not_found", "This device request is unavailable.", status: 404) }
        let expired = entry.request.value.expiresAt <= now() && entry.state == "pending"
        let revoked = clients[entry.request.value.clientID]?.revoked == true && entry.state == "approved"
        let state = revoked ? "revoked" : (expired ? "expired" : entry.state)
        return try crypto.sign(EnrollmentStatus(request: entry.request.value, state: state, grant: state == "approved" ? entry.grant : nil), domain: "enrollment-status", privateKey: privateKey)
    }
    public func cancel(_ signed: SignedValue<EnrollmentRequest>) throws -> SignedValue<EnrollmentStatus> {
        _ = try status(signed)
        guard pending[signed.value.requestID]?.state == "pending" else { throw BridgeError("request_finished", "This request has already been decided.", status: 409) }
        pending[signed.value.requestID]?.state = "cancelled"; return try status(signed)
    }
    public func pendingRequests() -> [EnrollmentRequest] {
        pending.values.filter { $0.state == "pending" && $0.request.value.expiresAt > now() }.map { $0.request.value }.sorted { $0.requestID < $1.requestID }
    }
    public func approve(requestID: String, scope: ClientScope) throws {
        try scope.validate()
        guard let entry = pending[requestID], entry.state == "pending", entry.request.value.expiresAt > now(),
              let window, window.windowID == entry.request.value.windowID, window.expiresAt > now() else { throw BridgeError("request_expired", "The exact pending device request is no longer available.", status: 409) }
        let request = entry.request.value
        guard Set(scope.workspaces).isSubset(of: Set(request.scope.workspaces)), Set(scope.capabilities).isSubset(of: Set(request.scope.capabilities)) else { throw BridgeError("invalid_scope", "Approval cannot expand the client's requested scope.") }
        guard clients[request.clientID] != nil || clients.count < 100 else { throw BridgeError("registry_capacity", "The device registry is full.", status: 409) }
        let grant = try crypto.sign(EnrollmentGrant(request: request, scope: scope, issuedAt: now()), domain: "grant", privateKey: privateKey)
        var updated = clients
        updated[request.clientID] = EnrolledClient(id: request.clientID, publicKey: request.clientPublicKey, name: request.clientName, kind: request.clientKind, scope: scope, revoked: false, grant: grant)
        try persist(updated); clients = updated; pending[requestID]?.state = "approved"; pending[requestID]?.grant = grant
    }
    public func deny(requestID: String) throws {
        guard let entry = pending[requestID], entry.state == "pending", entry.request.value.expiresAt > now() else { throw BridgeError("request_expired", "The device request is no longer pending.", status: 409) }
        pending[requestID]?.state = "denied"
    }
    public func enrolledClients() -> [EnrolledClient] { clients.values.sorted { $0.id < $1.id } }
    public func revoke(clientID: String) throws {
        guard clients[clientID] != nil else { throw BridgeError("client_not_found", "No enrolled device matched.", status: 404) }
        var updated = clients; updated[clientID]?.revoked = true
        try persist(updated); clients = updated
    }
    public func authorize(header: String?, method: String, uri: String, body: Data) throws -> EnrolledClient {
        guard let header, header.hasPrefix("CmuxV2 "), header.utf8.count <= 4096, let bytes = Data(base64Encoded: String(header.dropFirst(7))),
              let signed = try? JSONDecoder().decode(SignedValue<RequestProof>.self, from: bytes), let client = clients[signed.value.clientID], !client.revoked else { throw BridgeError("unauthorized", "This device is not authorized.", status: 401) }
        let proof = signed.value
        try crypto.verify(signed, domain: "request", publicKey: client.publicKey)
        guard proof.hostID == host.id, proof.epoch == epoch, proof.method == method, proof.uri == uri, proof.bodySHA256 == crypto.digest(body), UUID(uuidString: proof.nonce) != nil,
              proof.timestamp >= now() - 60, proof.timestamp <= now() + 60 else { throw BridgeError("invalid_proof", "The request identity, epoch or content changed.", status: 401) }
        usedNonces = usedNonces.filter { $0.value > now() }
        let nonceKey = client.id + ":" + proof.nonce
        guard usedNonces[nonceKey] == nil else { throw BridgeError("replayed_request", "This signed request was already used.", status: 409) }
        guard usedNonces.count < 4096 else { throw BridgeError("proof_capacity", "Too many requests. Try later.", status: 429) }
        usedNonces[nonceKey] = proof.timestamp + 61
        return client
    }
    public func require(_ clientID: String, capability: ClientCapability, workspace: String? = nil) throws -> EnrolledClient {
        guard let client = clients[clientID], !client.revoked else { throw BridgeError("unauthorized", "This device authorization was revoked.", status: 401) }
        guard client.scope.capabilities.contains(capability), workspace.map({ client.scope.workspaces.contains($0.lowercased()) }) ?? true else { throw BridgeError("scope_denied", "This device is not approved for this operation or workspace.", status: 403) }
        return client
    }
    private func verifyRequest(_ signed: SignedValue<EnrollmentRequest>, allowExpired: Bool = false) throws {
        let request = signed.value
        guard request.hostID == host.id, try crypto.identityID(publicKey: request.clientPublicKey) == request.clientID,
              UUID(uuidString: request.requestID) != nil, UUID(uuidString: request.nonce) != nil, UUID(uuidString: request.windowID) != nil,
              ["iphone", "mac"].contains(request.clientKind), !request.clientName.isEmpty, request.clientName.utf8.count <= 128,
              !request.clientName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              allowExpired || (request.expiresAt > now() && request.expiresAt <= now() + 600) else { throw BridgeError("invalid_enrollment", "The device enrollment request is invalid.") }
        try request.scope.validate(); try crypto.verify(signed, domain: "enrollment-request", publicKey: request.clientPublicKey)
    }
    private func persist(_ updated: [String: EnrolledClient]) throws {
        try JSONEncoder().encode(updated.values.sorted { $0.id < $1.id }).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
