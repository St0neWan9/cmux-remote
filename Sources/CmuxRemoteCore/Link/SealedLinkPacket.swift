import Foundation

/// Encapsulation appears exactly once for each ordered HPKE direction.
public struct SealedLinkPacket: Codable, Sendable {
    public let encapsulatedKey: Data?
    public let ciphertext: Data
    public init(encapsulatedKey: Data?, ciphertext: Data) { self.encapsulatedKey = encapsulatedKey; self.ciphertext = ciphertext }
}
