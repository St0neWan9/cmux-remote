import Foundation

/// Equality digest over the exact bytes a subscribed resource answered with.
///
/// Answers are encoded with sorted keys, so equal answers are equal bytes and need no semantic
/// normalization; decoding each answer into `JSONValue` and re-encoding it cost a full parse and encode
/// per tick to settle one equality question.
public struct LinkObservationDigest: Sendable {
    public init() {}
    public func digest(_ data: Data) throws -> String {
        guard data.count <= 8_388_608 else { throw BridgeError("too_large", "The observed resource exceeds its bound.") }
        return IdentityCryptography().digest(data)
    }
}
