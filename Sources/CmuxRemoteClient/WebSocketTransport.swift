import Foundation
import CmuxRemoteCore

/// The same encrypted resource transport is used for direct and relayed connections.
final class WebSocketTransport: ResourceTransport {
    private let connection: LinkClientConnection
    init(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relayDial: @escaping @Sendable (URL, [String: String]) -> LinkSocket = { LinkSocket(url: $0, headers: $1, timeout: 15) },
         report: @escaping @Sendable (LinkState) -> Void = { _ in }, trace: @escaping @Sendable (String) -> Void = { _ in }, lanDeadline: Duration = .seconds(4)) {
        connection = LinkClientConnection(host: host, key: key, endpoint: endpoint, relayDial: relayDial, report: report, trace: trace, lanDeadline: lanDeadline)
    }
    func reconnect() async { await connection.reconnect() }
    func updateRelay(_ relay: RelayEndpoint?) async { await connection.updateRelay(relay) }
    func exchange(_ path: String, method: String, query: [String: String], body: Data?, authorization: (@Sendable (String, Data) throws -> String)?) async throws -> LinkResourceResponse {
        let uri = try resourceURI(path, query: query)
        return try await connection.exchange(LinkFrame(kind: "request", id: UUID().uuidString, method: method, uri: uri, authorization: authorization?(uri, body ?? Data()), data: body))
    }
    func subscribe(_ path: String, query: [String: String], authorization: @escaping @Sendable (String, Data) throws -> String) async throws -> AsyncThrowingStream<LinkFrame, any Error> {
        let uri = try resourceURI(path, query: query)
        return try await connection.subscribe(LinkFrame(kind: "subscribe", id: UUID().uuidString, method: "GET", uri: uri, authorization: authorization(uri, Data())))
    }
    func close() { let connection = connection; Task { await connection.close() } }
    deinit { let connection = connection; Task { await connection.close() } }
    private func resourceURI(_ path: String, query: [String: String]) throws -> String {
        guard path.hasPrefix("/v2/"), !path.contains("..") else { throw BridgeError("invalid_route", "Invalid link resource route.") }
        var parts = URLComponents(); parts.path = path
        parts.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
}
