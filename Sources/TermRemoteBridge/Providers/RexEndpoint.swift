import Foundation
import TermRemoteCore

/// A Rex server endpoint. Rex listens on a Unix socket locally, or on an
/// explicit TCP/tailnet listener. SSH endpoints are deliberately unsupported
/// in this phase because they would spawn a transport process.
public enum RexEndpoint: Sendable, Equatable {
    case unix(path: String)
    case tcp(host: String, port: Int, tls: Bool)

    public var display: String {
        switch self {
        case .unix(let path): return "unix://" + path
        case .tcp(let host, let port, let tls): return (tls ? "https://" : "http://") + host + ":" + String(port)
        }
    }

    public var hostHeader: String {
        switch self {
        case .unix: return "localhost"
        case .tcp(let host, let port, let tls): return (tls || port != 80 ? host + ":" + String(port) : host)
        }
    }

    public static func parse(_ text: String) throws -> RexEndpoint {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2_048 else {
            throw BridgeError("invalid_endpoint", "A Rex endpoint is required.", status: 400)
        }
        if value.hasPrefix("unix://") || value.hasPrefix("unix:") {
            let raw = value.hasPrefix("unix://") ? String(value.dropFirst("unix://".count)) : String(value.dropFirst("unix:".count))
            let decoded = raw.removingPercentEncoding ?? raw
            let path = decoded.hasPrefix("/") ? decoded : "/" + decoded
            guard path.utf8.count <= 1_024, !path.contains("\u{0}") else {
                throw BridgeError("invalid_endpoint", "The Rex socket path is invalid.", status: 400)
            }
            return .unix(path: path)
        }
        guard let components = URLComponents(string: value), let host = components.host, !host.isEmpty,
              components.path.isEmpty || components.path == "/", components.query == nil else {
            throw BridgeError("invalid_endpoint", "Use unix:/path, http://host:port or https://host.", status: 400)
        }
        let scheme = components.scheme?.lowercased() ?? "http"
        guard scheme == "http" || scheme == "https" else {
            throw BridgeError("rex_unsupported", "This Rex transport is not supported yet.", status: 422)
        }
        let defaultPort = scheme == "https" ? 443 : 7_297
        let port = components.port ?? defaultPort
        guard (1...65_535).contains(port), host.utf8.count <= 253 else {
            throw BridgeError("invalid_endpoint", "The Rex port is invalid.", status: 400)
        }
        return .tcp(host: host, port: port, tls: scheme == "https")
    }
}
