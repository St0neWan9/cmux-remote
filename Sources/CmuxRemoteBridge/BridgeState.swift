import Foundation
import Security
import CryptoKit
import CmuxRemoteCore

/// Owner-only local credentials, independent from cmux account state.
public struct BridgeState: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var certificate: String { directory.appendingPathComponent("server.pem").path }
    public var key: String { directory.appendingPathComponent("server.key").path }
    public func initialize() throws {
        let tokenFile = directory.appendingPathComponent("token")
        guard !FileManager.default.fileExists(atPath: tokenFile.path) else { throw BridgeError("already_initialized", "State already exists; it was not overwritten.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BridgeError("initialization_failed", "Could not generate a pairing credential.") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try Data(token.utf8).write(to: tokenFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes", "-days", "365", "-subj", "/CN=cmux-remote", "-keyout", key, "-out", certificate])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key)
        try openssl(["x509", "-in", certificate, "-outform", "DER", "-out", directory.appendingPathComponent("server.der").path])
    }
    public func authority(name: String) throws -> ConnectionAuthority {
        let keyFile = directory.appendingPathComponent("host-identity.key")
        let crypto = IdentityCryptography()
        let privateKey: Data
        if FileManager.default.fileExists(atPath: keyFile.path) { privateKey = try Data(contentsOf: keyFile) }
        else {
            privateKey = crypto.generatePrivateKey()
            try privateKey.write(to: keyFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        }
        let publicKey = try crypto.publicKey(privateKey: privateKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: publicKey), publicKey: publicKey, certificateSHA256: crypto.digest(try Data(contentsOf: directory.appendingPathComponent("server.der"))), name: name)
        return try ConnectionAuthority(host: host, privateKey: privateKey, registryFile: directory.appendingPathComponent("clients.json"))
    }
    public func token() throws -> String { try String(contentsOf: directory.appendingPathComponent("token"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
    public func pairing(host: String, port: Int) throws -> PairingConfiguration {
        let data = try Data(contentsOf: directory.appendingPathComponent("server.der"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try PairingConfiguration(host: host, port: port, token: token(), certificateSHA256: digest)
    }
    private func openssl(_ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BridgeError("initialization_failed", "TLS certificate initialization failed.") }
    }
}
