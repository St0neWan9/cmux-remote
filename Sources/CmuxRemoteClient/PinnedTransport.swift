import Foundation
import CmuxRemoteCore

/// Exact certificate/endpoint pinning applies before enrollment or authenticated payloads are sent.
final class PinnedTransport: Sendable {
    private let pairing: PairingConfiguration
    private let session: URLSession
    init(pairing: PairingConfiguration) {
        self.pairing = pairing
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20; configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: PinnedSessionDelegate(pairing: pairing), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func close() { session.invalidateAndCancel() }
    func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String] = [:], body: Data? = nil, authorization: (@Sendable (String, Data) throws -> String)? = nil, as: T.Type) async throws -> T {
        guard path.hasPrefix("/v1/") || path.hasPrefix("/v2/"), !path.contains(".."),
              let base = pairing.baseURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw BridgeError("invalid_route", "Invalid resource URL.") }
        components.path = path; components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw BridgeError("invalid_route", "Invalid resource URL.") }
        let uri = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if let authorization { request.setValue(try authorization(uri, body ?? Data()), forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard data.count <= 8_388_608, let response = response as? HTTPURLResponse else { throw BridgeError("invalid_response", "The response exceeds the read limit.", status: 502) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard response.statusCode == 200 else {
            let object = try? decoder.decode(JSONValue.self, from: data)
            throw BridgeError(object?["error"]["code"].string ?? "connection_failed", object?["error"]["message"].string ?? "The Bridge could not complete the request.", status: response.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
