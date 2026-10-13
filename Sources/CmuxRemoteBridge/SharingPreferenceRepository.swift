import Foundation
import Darwin
import CmuxRemoteCore

/// The owner's last explicit sharing choice; a listener failure is not a choice and is never recorded.
public struct SharingPreferenceRepository: Sendable {
    public struct Preference: Codable, Sendable, Equatable {
        public let enabled: Bool
        public let port: Int
        public init(enabled: Bool, port: Int) { self.enabled = enabled; self.port = port }
    }
    private let file: URL
    public init(directory: URL) { file = directory.appendingPathComponent("sharing.json") }
    /// A missing, foreign or malformed file means sharing stays off, as before this preference existed.
    public func load() -> Preference? {
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size <= 256,
              let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(Preference.self, from: data),
              (1...65535).contains(value.port) else { return nil }
        return value
    }
    public func save(_ value: Preference) throws {
        let temporary = file.deletingLastPathComponent().appendingPathComponent("sharing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(value).write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, file.path) == 0 else { throw BridgeError("state_unavailable", "Could not save the sharing preference.") }
    }
}
