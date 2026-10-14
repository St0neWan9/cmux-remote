import Foundation
import CmuxRemoteCore

/// A bounded resource exchange independent of the selected network path.
protocol ResourceTransport: Sendable {
    func exchange(_ path: String, method: String, query: [String: String], body: Data?, authorization: (@Sendable (String, Data) throws -> String)?) async throws -> LinkResourceResponse
    func close()
    /// Drops a link that may be dead and dials again; a request-per-call transport has nothing to drop.
    func reconnect() async
}
extension ResourceTransport {
    func reconnect() async {}
    func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String] = [:], body: Data? = nil, authorization: (@Sendable (String, Data) throws -> String)? = nil, as: T.Type) async throws -> T {
        let response = try await exchange(path, method: method, query: query, body: body, authorization: authorization)
        try validate(response)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: response.data)
    }
    func image(_ path: String, query: [String: String], authorization: @escaping @Sendable (String, Data) throws -> String) async throws -> Data {
        let response = try await exchange(path, method: "GET", query: query, body: nil, authorization: authorization)
        try validate(response)
        guard response.data.count <= 524_288, response.contentType.split(separator: ";").first == "image/jpeg", response.data.count >= 3,
              response.data.prefix(3) == Data([0xff, 0xd8, 0xff]) else { throw BridgeError("invalid_response", "Invalid image response.", status: 502) }
        return response.data
    }
    private func validate(_ response: LinkResourceResponse) throws {
        guard response.data.count <= 8_388_608 else { throw BridgeError("invalid_response", "The response exceeds its bound.", status: 502) }
        guard response.status == 200 else {
            let error = try? JSONDecoder().decode(JSONValue.self, from: response.data)["error"]
            throw BridgeError(error?["code"].string ?? "connection_failed", "The Bridge rejected the resource request.", status: response.status)
        }
    }
}
