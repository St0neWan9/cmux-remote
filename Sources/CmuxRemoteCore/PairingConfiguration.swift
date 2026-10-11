import Foundation

/// Local device credentials and the exact SHA-256 TLS certificate pin.
public struct PairingConfiguration: Codable, Sendable, Equatable {
    public let host: String
    public let port: Int
    public let token: String
    public let certificateSHA256: String
    public init(host: String, port: Int, token: String, certificateSHA256: String) throws {
        guard !host.isEmpty, !host.contains("/"), !host.contains("@"), (1...65535).contains(port),
              token.utf8.count >= 32, certificateSHA256.count == 64,
              certificateSHA256.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw BridgeError("invalid_pairing", "Check the host, port, token and certificate fingerprint.")
        }
        self.host = host; self.port = port; self.token = token; self.certificateSHA256 = certificateSHA256.lowercased()
    }
    public var baseURL: URL {
        var c = URLComponents(); c.scheme = "https"; c.host = host; c.port = port
        return c.url!
    }
}
