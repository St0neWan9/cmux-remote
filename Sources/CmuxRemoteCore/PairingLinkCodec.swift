import Foundation

/// A versioned QR payload validated before any network connection is attempted.
public struct PairingLinkCodec: Sendable {
    public init() {}
    public func encode(_ pairing: PairingConfiguration) throws -> String {
        let data = try JSONEncoder().encode(pairing)
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "cmux-remote://pair?v=1&payload=" + payload
    }
    public func decode(_ text: String) throws -> PairingConfiguration {
        guard text.utf8.count <= 4096, let url = URLComponents(string: text), url.scheme == "cmux-remote", url.host == "pair", url.path.isEmpty,
              let items = url.queryItems, items.count == 2, items.first(where: { $0.name == "v" })?.value == "1",
              let payload = items.first(where: { $0.name == "payload" })?.value else { throw invalid() }
        let decoded = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - decoded.count % 4) % 4)
        guard let data = Data(base64Encoded: decoded + padding), let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data) else { throw invalid() }
        return try PairingConfiguration(host: value.host, port: value.port, token: value.token, certificateSHA256: value.certificateSHA256)
    }
    private func invalid() -> BridgeError { BridgeError("invalid_pairing", "This QR code is not a supported cmux remote pairing code.") }
}
