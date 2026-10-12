import Foundation

/// Version 2 QR codes supply host trust and an expiring enrollment window, never a bearer token.
public struct EnrollmentLinkCodec: Sendable {
    public init() {}
    public func encode(_ bootstrap: SignedValue<EnrollmentBootstrap>) throws -> String {
        let payload = try JSONEncoder().encode(bootstrap).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "cmux-remote://enroll?v=2&payload=" + payload
    }
    public func decode(_ text: String, now: Int = Int(Date().timeIntervalSince1970)) throws -> SignedValue<EnrollmentBootstrap> {
        guard text.utf8.count <= 8192, let url = URLComponents(string: text), url.scheme == "cmux-remote", url.host == "enroll", url.path.isEmpty,
              let items = url.queryItems, items.count == 2, items.first(where: { $0.name == "v" })?.value == "2",
              let payload = items.first(where: { $0.name == "payload" })?.value else { throw BridgeError("invalid_pairing", "Scan a version 2 enrollment QR code.") }
        let encoded = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)), let value = try? JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: data) else { throw BridgeError("invalid_pairing", "The QR code is invalid.") }
        try validate(value, now: now); return value
    }
    public func validate(_ bootstrap: SignedValue<EnrollmentBootstrap>, now: Int) throws {
        let value = bootstrap.value
        try ClientScope(workspaces: value.workspaces, capabilities: [.workspaceRead]).validate()
        try value.endpoint.validate(); try IdentityCryptography().validate(value.host)
        guard value.version == 2, UUID(uuidString: value.windowID) != nil, value.expiresAt > now, value.expiresAt - now <= 600 else { throw BridgeError("enrollment_expired", "Open a new enrollment window on the Mac.") }
        try IdentityCryptography().verify(bootstrap, domain: "bootstrap", publicKey: value.host.publicKey)
    }
}
