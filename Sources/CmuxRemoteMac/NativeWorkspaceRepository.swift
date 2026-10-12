import Foundation
import CmuxRemoteCore

/// Persists catalog creation intents before native writes, without credentials.
public actor NativeWorkspaceRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> [NativeWorkspaceEntry] {
        let path = directory.appendingPathComponent("native-workspaces.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 4_194_304 else { throw BridgeError("invalid_state", "Native workspace state exceeds its limit.") }
        let rows = try JSONDecoder().decode([NativeWorkspaceEntry].self, from: bytes)
        guard rows.count <= 4096, Set(rows.map(\.id)).count == rows.count,
              Set(rows.map { $0.hostID + ":" + $0.workspaceID }).count == rows.count,
              rows.allSatisfy({ row in
                  row.hostID.count == 64 && row.hostID.allSatisfy({ $0.isASCII && $0.isHexDigit }) &&
                  UUID(uuidString: row.workspaceID) != nil && row.title.utf8.count <= 4096 &&
                  ["creating", "pending", "attaching", "attached", "paused", "unavailable"].contains(row.state) &&
                  (row.seed.map { seed in [seed.workspaceID, seed.surfaceID, seed.windowID].allSatisfy { UUID(uuidString: $0) != nil } } ?? true) &&
                  (row.errorCode?.utf8.count ?? 0) <= 256
              }) else {
            throw BridgeError("invalid_state", "Invalid native workspace bindings.")
        }
        return rows
    }
    public func save(_ rows: [NativeWorkspaceEntry]) throws {
        guard rows.count <= 4096 else { throw BridgeError("mirror_capacity", "The native workspace catalog is full.", status: 429) }
        let bytes = try JSONEncoder().encode(rows)
        guard bytes.count <= 4_194_304 else { throw BridgeError("mirror_capacity", "The native workspace catalog exceeds its limit.", status: 429) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("native-workspaces.json")
        try bytes.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
