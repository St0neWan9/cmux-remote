import Foundation

/// Canonical HTTPS origin; credentials, paths and URL query routing are forbidden.
public struct RelayOrigin: Sendable, Equatable {
    public let value: String
    public init(_ value: String) throws {
        guard var parts = URLComponents(string: value), parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", (parts.port.map { (1...65535).contains($0) } ?? true), value.utf8.count <= 512 else { throw BridgeError("invalid_endpoint", "Use an HTTPS relay origin without credentials or a path.") }
        parts.host = host.lowercased(); parts.path = ""; if parts.port == 443 { parts.port = nil }
        guard let origin = parts.url?.absoluteString else { throw BridgeError("invalid_endpoint", "Invalid relay origin.") }
        self.value = origin
    }
    /// Hosts listed while online; each entry is host-signed and checked again by the reader.
    public func directoryURL() throws -> URL {
        guard var parts = URLComponents(string: value) else { throw BridgeError("invalid_endpoint", "Invalid relay route.") }
        parts.path = "/v3/directory"
        guard let url = parts.url else { throw BridgeError("invalid_endpoint", "Invalid relay route.") }; return url
    }
    public func socketURL(hostID: String, role: String) throws -> URL {
        guard hostID.count == 64, hostID.allSatisfy({ $0.isASCII && $0.isHexDigit }), ["bridge", "client"].contains(role),
              var parts = URLComponents(string: value) else { throw BridgeError("invalid_endpoint", "Invalid relay route.") }
        parts.scheme = "wss"; parts.path = "/v3/relay/" + hostID.lowercased(); parts.queryItems = [URLQueryItem(name: "role", value: role)]
        guard let url = parts.url else { throw BridgeError("invalid_endpoint", "Invalid relay route.") }; return url
    }
}
