import Foundation
import CmuxRemoteCore

/// Shared iPhone/Mac signed client. Reconnect never retries a mutation automatically.
public final class RemoteClient: Sendable {
    private let transport: PinnedTransport
    private let pairing: PairingConfiguration
    private let connection: AuthorizedConnection?
    /// Explicit legacy mode for old pairings; the Bridge must separately enable legacy access.
    public init(pairing: PairingConfiguration) {
        self.pairing = pairing; connection = nil; transport = PinnedTransport(pairing: pairing)
    }
    public init(connection: AuthorizedConnection) throws {
        try connection.validate(); self.connection = connection
        pairing = try PairingConfiguration(host: connection.endpoint.host, port: connection.endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: connection.host.certificateSHA256)
        transport = PinnedTransport(pairing: pairing)
    }
    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T { try await request(path, method: "GET", query: query, body: nil, as: type) }
    public func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { try await request(path, method: "POST", query: [:], body: JSONEncoder().encode(body), as: type) }
    public var canControlConversations: Bool { connection?.grant.value.scope.capabilities.contains(.conversationControl) ?? true }
    public var canReplyFeed: Bool { connection?.grant.value.scope.capabilities.contains(.feedReply) ?? true }
    public func close() { transport.close() }
    private func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String], body: Data?, as type: T.Type) async throws -> T {
        guard path.hasPrefix("/v1/") else { throw BridgeError("invalid_route", "Invalid resource path.") }
        if let connection {
            // A signed fresh host epoch prevents replay across Bridge restarts. No mutation is sent yet.
            let announcement = try await transport.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
            let crypto = IdentityCryptography()
            try crypto.verify(announcement, domain: "host", publicKey: connection.host.publicKey)
            guard announcement.value.version == 2, announcement.value.host.id == connection.host.id,
                  announcement.value.host.publicKey == connection.host.publicKey, announcement.value.host.certificateSHA256 == connection.host.certificateSHA256,
                  UUID(uuidString: announcement.value.epoch) != nil else { throw BridgeError("host_changed", "The host identity changed. Pair again explicitly.") }
            return try await transport.request("/v2/" + path.dropFirst(4), method: method, query: query, body: body, authorization: { uri, bytes in
                let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: method, uri: uri, bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
                let signed = try crypto.sign(proof, domain: "request", privateKey: connection.privateKey)
                return "CmuxV2 " + (try JSONEncoder().encode(signed)).base64EncodedString()
            }, as: type)
        }
        let token = pairing.token
        return try await transport.request(path, method: method, query: query, body: body, authorization: { _, _ in "Bearer " + token }, as: type)
    }
}
