import Foundation
import CmuxRemoteCore

/// Exact certificate/endpoint pinning applies before enrollment or authenticated payloads are sent.
final class PinnedTransport: ResourceTransport {
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
    func image(_ path: String, query: [String: String], authorization: @escaping @Sendable (String, Data) throws -> String) async throws -> Data {
        let request = try makeRequest(path, method: "GET", query: query, body: nil, authorization: authorization)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw BridgeError("invalid_response", "The image response is invalid.", status: 502) }
        let limit = response.statusCode == 200 ? 524_288 : 65_536
        guard response.expectedContentLength <= Int64(limit) else { throw BridgeError("invalid_response", "The image response exceeds its limit.", status: 502) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw BridgeError("invalid_response", "The image response exceeds its limit.", status: 502) }
            data.append(byte)
        }
        if response.statusCode != 200 {
            let object = try? JSONDecoder().decode(JSONValue.self, from: data)
            throw BridgeError(object?["error"]["code"].string ?? "connection_failed", "The image could not be read.", status: response.statusCode)
        }
        guard response.mimeType == "image/jpeg", data.count >= 3, data.prefix(3) == Data([0xff, 0xd8, 0xff]) else { throw BridgeError("invalid_response", "The image response is not a supported JPEG.", status: 502) }
        return data
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String, query: [String: String] = [:], body: Data? = nil, authorization: (@Sendable (String, Data) throws -> String)? = nil, as: T.Type) async throws -> T {
        let request = try makeRequest(path, method: method, query: query, body: body, authorization: authorization)
        let (data, response) = try await session.data(for: request)
        guard data.count <= 8_388_608, let response = response as? HTTPURLResponse else { throw BridgeError("invalid_response", "The response exceeds the read limit.", status: 502) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard response.statusCode == 200 else {
            let object = try? decoder.decode(JSONValue.self, from: data)
            throw BridgeError(object?["error"]["code"].string ?? "connection_failed", object?["error"]["message"].string ?? "The Bridge could not complete the request.", status: response.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
    func exchange(_ path: String, method: String, query: [String: String], body: Data?, authorization: (@Sendable (String, Data) throws -> String)?) async throws -> LinkResourceResponse {
        let request = try makeRequest(path, method: method, query: query, body: body, authorization: authorization)
        let (bytes, raw) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = raw as? HTTPURLResponse, response.expectedContentLength <= 8_388_608 else { throw BridgeError("invalid_response", "The response exceeds its bound.", status: 502) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8_388_608 else { throw BridgeError("invalid_response", "The response exceeds its bound.", status: 502) }
            data.append(byte)
        }
        return LinkResourceResponse(status: response.statusCode, data: data, contentType: response.mimeType ?? "application/json")
    }
    private func makeRequest(_ path: String, method: String, query: [String: String], body: Data?, authorization: (@Sendable (String, Data) throws -> String)?) throws -> URLRequest {
        guard path.hasPrefix("/v1/") || path.hasPrefix("/v2/"), !path.contains(".."),
              let base = pairing.baseURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw BridgeError("invalid_route", "Invalid resource URL.") }
        components.path = path; components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw BridgeError("invalid_route", "Invalid resource URL.") }
        let uri = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if let authorization { request.setValue(try authorization(uri, body ?? Data()), forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
