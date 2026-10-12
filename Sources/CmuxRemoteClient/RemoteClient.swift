import Foundation
import CmuxRemoteCore

/// A stable shared client object; relocation changes transport without stranding open views.
public final class RemoteClient: Sendable {
    private let runtime: RemoteClientRuntime
    /// Host and device namespace for private pending operations; relocation keeps it stable.
    public let operationRecoveryScope: String
    public let canControlConversations: Bool
    public let canReplyFeed: Bool
    private let capabilities: Set<ClientCapability>
    public func allows(_ capability: ClientCapability) -> Bool { capabilities.contains(capability) }
    /// Explicit legacy mode; the owner must separately enable it on the Bridge.
    public init(pairing: PairingConfiguration) {
        operationRecoveryScope = IdentityCryptography().digest(Data((pairing.certificateSHA256 + ":" + pairing.token).utf8))
        runtime = RemoteClientRuntime(pairing: pairing, connection: nil); canControlConversations = true; canReplyFeed = true; capabilities = Set(ClientCapability.allCases)
    }
    public init(connection: AuthorizedConnection) throws {
        try connection.validate()
        operationRecoveryScope = IdentityCryptography().digest(try JSONEncoder().encode([connection.host.id, connection.grant.value.clientID]))
        let pairing = try PairingConfiguration(host: connection.endpoint.host, port: connection.endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: connection.host.certificateSHA256)
        runtime = RemoteClientRuntime(pairing: pairing, connection: connection)
        capabilities = Set(connection.grant.value.scope.capabilities)
        canControlConversations = connection.grant.value.scope.capabilities.contains(.conversationControl)
        canReplyFeed = connection.grant.value.scope.capabilities.contains(.feedReply)
    }
    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T { try await runtime.request(path, method: "GET", query: query, body: nil, as: type) }
    public func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { try await runtime.request(path, method: "POST", query: [:], body: JSONEncoder().encode(body), as: type) }
    public func relocate(_ connection: AuthorizedConnection) async throws { try await runtime.relocate(connection) }
    public func close() { let runtime = runtime; Task { await runtime.close() } }
    deinit { let runtime = runtime; Task { await runtime.close() } }
}
