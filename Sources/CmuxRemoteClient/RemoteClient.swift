import Foundation
import CmuxRemoteCore

/// Typed HTTPS client with endpoint pinning and no automatic mutation retries.
public final class RemoteClient: Sendable {
    private let pairing: PairingConfiguration
    private let session: URLSession
    public init(pairing: PairingConfiguration) {
        self.pairing = pairing
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration, delegate: PinnedSessionDelegate(pairing: pairing), delegateQueue: nil)
    }
    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        try await request(path, method: "GET", query: query, body: nil, as: type)
    }
    public func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await request(path, method: "POST", query: [:], body: JSONEncoder().encode(body), as: type)
    }
    public func close() { session.invalidateAndCancel() }
    private func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String], body: Data?, as type: T.Type) async throws -> T {
        guard path.hasPrefix("/v1/"), !path.contains("..") else { throw BridgeError("invalid_route", "Invalid resource path.") }
        var components = URLComponents(url: pairing.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path; components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + pairing.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard data.count <= 8_388_608, let response = response as? HTTPURLResponse else { throw BridgeError("invalid_response", "The response exceeds the read limit.", status: 502) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard response.statusCode == 200 else {
            if let object = try? decoder.decode(JSONValue.self, from: data) {
                throw BridgeError(object["error"]["code"].string ?? "connection_failed", object["error"]["message"].string ?? "The Bridge could not complete the request.", status: response.statusCode)
            }
            throw BridgeError("connection_failed", "The Bridge could not complete the request.", status: response.statusCode)
        }
        return try decoder.decode(type, from: data)
    }
}
