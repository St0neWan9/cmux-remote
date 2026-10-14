import Foundation
import CmuxRemoteCore

/// Mutable endpoint ownership stays in one actor while existing views retain their client object.
actor RemoteClientRuntime {
    private var transport: any ResourceTransport
    private var pairing: PairingConfiguration
    private var connection: AuthorizedConnection?
    private var announcement: SignedValue<HostAnnouncement>?
    private var closed = false
    nonisolated let linkStates = LinkStateBroadcaster()
    init(pairing: PairingConfiguration, connection: AuthorizedConnection?) {
        self.pairing = pairing; self.connection = connection
        let states = linkStates
        if let connection { transport = WebSocketTransport(host: connection.host, key: connection.privateKey, endpoint: connection.endpoint, report: { states.report($0) }) }
        else { transport = PinnedTransport(pairing: pairing) }
    }
    func close() { closed = true; transport.close(); linkStates.finish() }
    func reconnect() async { guard !closed else { return }; announcement = nil; await transport.reconnect() }
    func relocate(_ updated: AuthorizedConnection) throws {
        guard !closed, let current = connection, current.privateKey == updated.privateKey,
              current.grant.signature == updated.grant.signature, current.grant.value == updated.grant.value else { throw BridgeError("host_changed", "Relocation cannot replace the device or its authorization.") }
        _ = try current.relocated(to: updated.endpoint, advertisedHost: updated.host)
        try updated.validate()
        let endpoint = try PairingConfiguration(host: updated.endpoint.host, port: updated.endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: updated.host.certificateSHA256)
        // In-flight requests own their old transport until completion; endpoint changes do not retry/cancel writes.
        // The new endpoint may be a restarted Bridge with a fresh epoch, so the cached announcement cannot be reused.
        announcement = nil
        let states = linkStates
        transport = WebSocketTransport(host: updated.host, key: updated.privateKey, endpoint: updated.endpoint, report: { states.report($0) }); pairing = endpoint; connection = updated
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String], body: Data?, as type: T.Type) async throws -> T {
        do { return try await attempt(path, method: method, query: query, body: body, as: type) }
        catch let error as BridgeError where error.code == "invalid_proof" && dropStaleEpoch() {
            // A restarted Bridge has a new epoch while the link to it stays up, so the cached one signs every
            // request wrong. The proof is checked before any route acts, so the rejected request did nothing
            // and is sent once more under the epoch fetched afresh.
            return try await attempt(path, method: method, query: query, body: body, as: type)
        }
    }
    private func attempt<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String], body: Data?, as type: T.Type) async throws -> T {
        let request = try await authorized(path, method: method)
        do { return try await request.transport.request(request.path, method: method, query: query, body: body, authorization: request.authorization, as: type) }
        catch {
            if method == "POST", !(error is BridgeError) { throw BridgeError("outcome_unknown", "Inspect the task before repeating this operation.", status: 504) }
            throw error
        }
    }
    /// Forgets the cached epoch; false when none was cached, so a rejection under a fresh one is final.
    private func dropStaleEpoch() -> Bool {
        guard announcement != nil else { return false }
        announcement = nil; return true
    }
    func savedConnection() -> AuthorizedConnection? { connection }
    /// Learn a signed routing proof without replacing an in-flight transport or device grant.
    func refreshRelayHint() async throws -> AuthorizedConnection? {
        guard let original = connection else { return nil }
        let signed = try await request("/v1/relay", method: "GET", query: [:], body: nil, as: SignedValue<RelayHint>.self)
        let crypto = IdentityCryptography(); try crypto.verify(signed, domain: "relay3-hint", publicKey: original.host.publicKey)
        guard !closed, let current = connection, current.host.id == original.host.id, current.grant.signature == original.grant.signature,
              signed.value.hostID == current.host.id, signed.value.clientID == current.grant.value.clientID,
              UUID(uuidString: signed.value.epoch) != nil else { throw BridgeError("invalid_identity", "The reachability hint belongs to another connection.") }
        var updated = current; updated.endpoint.relay = signed.value.relay; try updated.validate()
        // A relocation while the await was in flight owns its new transport; update that actor too.
        if let link = transport as? WebSocketTransport { await link.updateRelay(updated.endpoint.relay) }
        connection = updated; return updated
    }
    func subscribe(_ path: String) async throws -> AsyncThrowingStream<LinkFrame, any Error> {
        do { return try await openSubscription(path) }
        catch let error as BridgeError where error.code == "invalid_proof" && dropStaleEpoch() { return try await openSubscription(path) }
    }
    private func openSubscription(_ path: String) async throws -> AsyncThrowingStream<LinkFrame, any Error> {
        let request = try await authorized(path, method: "GET")
        guard let link = request.transport as? WebSocketTransport else { throw BridgeError("unsupported", "This connection has no subscriptions.", status: 422) }
        return try await link.subscribe(request.path, query: [:], authorization: request.authorization)
    }
    func image(sessionID: String, reference: ConversationImageReference) async throws -> Data {
        do { return try await fetchImage(sessionID: sessionID, reference: reference) }
        catch let error as BridgeError where error.code == "invalid_proof" && dropStaleEpoch() { return try await fetchImage(sessionID: sessionID, reference: reference) }
    }
    private func fetchImage(sessionID: String, reference: ConversationImageReference) async throws -> Data {
        let path = "/v1/sessions/\(sessionID)/image"
        let request = try await authorized(path, method: "GET")
        return try await request.transport.image(request.path, query: ["reference_id": reference.id, "generation": reference.generation], authorization: request.authorization)
    }
    private func authorized(_ path: String, method: String) async throws -> AuthorizedRequest {
        guard !closed else { throw URLError(.cancelled) }
        guard path.hasPrefix("/v1/") else { throw BridgeError("invalid_route", "Invalid resource path.") }
        let transport = transport; let connection = connection; let pairing = pairing
        if let connection {
            // The epoch is stable per Bridge process; fetch it once per live link to save a relay round-trip.
            let announcement: SignedValue<HostAnnouncement>
            if let cached = self.announcement {
                announcement = cached
            } else {
                let fetched = try await transport.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
                let crypto2 = IdentityCryptography(); try crypto2.verify(fetched, domain: "host", publicKey: connection.host.publicKey)
                guard fetched.value.version == 2, fetched.value.host.id == connection.host.id,
                      fetched.value.host.publicKey == connection.host.publicKey, fetched.value.host.certificateSHA256 == connection.host.certificateSHA256,
                      UUID(uuidString: fetched.value.epoch) != nil else { throw BridgeError("host_changed", "The host identity changed. Pair again explicitly.") }
                self.announcement = fetched; announcement = fetched
            }
            try Task.checkCancellation()
            let crypto = IdentityCryptography()
            return AuthorizedRequest(transport: transport, path: "/v2/" + path.dropFirst(4), authorization: { uri, bytes in
                let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: method, uri: uri, bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
                return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
            })
        }
        let token = pairing.token
        return AuthorizedRequest(transport: transport, path: path, authorization: { _, _ in "Bearer " + token })
    }
}
