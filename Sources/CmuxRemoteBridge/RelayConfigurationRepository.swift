import Foundation
import Darwin
import CmuxRemoteCore

/// Private owner configuration stores an origin and key pathname, never the deployment secret.
public struct RelayConfigurationRepository: Sendable {
    public struct Configuration: Codable, Sendable {
        public let origin: String
        public let keyFile: String
        public init(origin: String, keyFile: String) { self.origin = origin; self.keyFile = keyFile }
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> Configuration? {
        let file = directory.appendingPathComponent("relay.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let configuration = try JSONDecoder().decode(Configuration.self, from: privateRead(file.path, limit: 4096))
        _ = try RelayOrigin(configuration.origin); _ = try secret(configuration)
        return configuration
    }
    public func save(origin: String, keyFile: String) throws -> Configuration {
        let configuration = Configuration(origin: try RelayOrigin(origin).value, keyFile: keyFile)
        _ = try secret(configuration)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("relay.json")
        let temporary = directory.appendingPathComponent("relay-" + UUID().uuidString)
        let bytes = try JSONEncoder().encode(configuration)
        try bytes.write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, file.path) == 0 else { throw BridgeError("invalid_identity", "Could not save private relay configuration.") }
        return configuration
    }
    public func remove() throws {
        let file = directory.appendingPathComponent("relay.json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    public func secret(_ configuration: Configuration) throws -> String {
        let bytes = try privateRead(configuration.keyFile, limit: 512)
        guard let text = String(data: bytes, encoding: .utf8) else { throw BridgeError("invalid_identity", "Invalid relay key encoding.") }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...256).contains(value.utf8.count), value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw BridgeError("invalid_identity", "Use a private bounded relay key.") }
        return value
    }
    private func privateRead(_ path: String, limit: Int) throws -> Data {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw BridgeError("invalid_identity", "Use an absolute private relay key path.") }
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw BridgeError("invalid_identity", "The private relay configuration is unavailable.") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_size <= limit else { throw BridgeError("invalid_identity", "The relay key/configuration must be an owner-only regular file.") }
        var result = Data(), buffer = [UInt8](repeating: 0, count: min(limit + 1, 4096))
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { return result }
            guard count > 0, result.count + count <= limit else { throw BridgeError("invalid_identity", "The relay configuration exceeds its bound.") }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
