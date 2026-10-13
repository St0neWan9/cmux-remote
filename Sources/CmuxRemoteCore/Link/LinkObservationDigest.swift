import Foundation

/// Semantic JSON digest avoids false changes caused by encoder object-key ordering.
public struct LinkObservationDigest: Sendable {
    public init() {}
    public func digest(_ data: Data) throws -> String {
        guard data.count <= 8_388_608 else { throw BridgeError("too_large", "The observed resource exceeds its bound.") }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return IdentityCryptography().digest(try IdentityCryptography().bytes(value, domain: "link3-observation"))
    }
}
