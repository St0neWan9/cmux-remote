import Foundation

/// Public host trust, bound to a TLS leaf certificate and independent of its IP address.
public struct HostIdentity: Codable, Sendable, Equatable {
    public var id: String
    public var publicKey: String
    public var certificateSHA256: String
    public var name: String
    public init(id: String, publicKey: String, certificateSHA256: String, name: String) {
        self.id = id; self.publicKey = publicKey; self.certificateSHA256 = certificateSHA256; self.name = name
    }
}
