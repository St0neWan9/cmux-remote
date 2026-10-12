import Foundation
import CmuxRemoteCore

/// Persists only a boot ID and sequence, never events or conversation content.
public actor CmuxEventCursorRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> CmuxEventCursor? {
        let path = directory.appendingPathComponent("cmux-event-cursor.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 1024 else { throw BridgeError("event_resync", "Event cursor exceeds its limit.") }
        let cursor = try JSONDecoder().decode(CmuxEventCursor?.self, from: bytes)
        if let cursor { try validate(cursor) }
        return cursor
    }
    public func save(_ cursor: CmuxEventCursor?) throws {
        if let cursor { try validate(cursor) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("cmux-event-cursor.json")
        try JSONEncoder().encode(cursor).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    private func validate(_ cursor: CmuxEventCursor) throws {
        guard !cursor.bootID.isEmpty, cursor.bootID.utf8.count <= 128, !cursor.bootID.contains("\n"), cursor.sequence >= 0 else { throw BridgeError("event_resync", "Invalid cmux event cursor.") }
    }
}
