import Foundation
import CryptoKit

/// Ed25519 signatures and SHA-256 identity names shared by host and clients.
public struct IdentityCryptography: Sendable {
    public init() {}
    public func generatePrivateKey() -> Data { Curve25519.Signing.PrivateKey().rawRepresentation }
    public func publicKey(privateKey: Data) throws -> String { try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation.base64EncodedString() }
    public func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public func identityID(publicKey: String) throws -> String {
        guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else { throw BridgeError("invalid_identity", "The public identity is invalid.") }
        return digest(bytes)
    }
    public func bytes<T: Encodable>(_ value: T, domain: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var bytes = Data(("cmux-remote/2/" + domain + "\n").utf8); bytes.append(try encoder.encode(value)); return bytes
    }
    public func sign<T: Codable & Sendable>(_ value: T, domain: String, privateKey: Data) throws -> SignedValue<T> {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return SignedValue(value: value, signature: try key.signature(for: bytes(value, domain: domain)).base64EncodedString())
    }
    public func verify<T>(_ signed: SignedValue<T>, domain: String, publicKey: String) throws {
        guard let key = Data(base64Encoded: publicKey), key.count == 32, let signature = Data(base64Encoded: signed.signature), signature.count == 64,
              try Curve25519.Signing.PublicKey(rawRepresentation: key).isValidSignature(signature, for: bytes(signed.value, domain: domain)) else {
            throw BridgeError("invalid_signature", "The identity proof could not be verified.", status: 401)
        }
    }
    public func validate(_ host: HostIdentity) throws {
        guard try identityID(publicKey: host.publicKey) == host.id,
              host.certificateSHA256.count == 64, host.certificateSHA256.allSatisfy({ $0.isASCII && $0.isHexDigit }), !host.name.isEmpty, host.name.utf8.count <= 128 else {
            throw BridgeError("invalid_identity", "The host identity is invalid.")
        }
    }
}
