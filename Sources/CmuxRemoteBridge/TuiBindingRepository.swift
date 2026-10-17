import Foundation
import Darwin
import CryptoKit
import CmuxRemoteCore

/// Private metadata archive; old bindings are history-only until a fresh daemon proves them live.
public struct TuiBindingRepository: Sendable {
    private struct Archive: Codable { let identity: String; let rows: [TuiSessionSnapshot.Binding] }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    func load(identity: String) throws -> [TuiSessionSnapshot.Binding] {
        let file = path(identity)
        let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return [] }
        guard fd >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size <= 1_048_576 else { throw invalid() }
        let archive = try JSONDecoder().decode(Archive.self, from: handle.readToEnd() ?? Data())
        guard archive.identity == identity, archive.rows.count <= 200,
              archive.rows.allSatisfy({ $0.id.hasPrefix("tui:") && UUID(uuidString: $0.providerSession) != nil && ["claude", "codex"].contains($0.provider) && $0.title.utf8.count <= 8192 && ($0.cwd?.utf8.count ?? 0) <= 8192 }) else { throw invalid() }
        // A conversation is now identified by its Agent session rather than its terminal, so an archive written by an
        // older Bridge is re-keyed on load; rows that collapse onto one Agent keep the newest and take its identity.
        let migrated = migrate(archive.rows, identity: identity)
        guard Set(migrated.map(\.id)).count == migrated.count else { throw invalid() }
        return migrated
    }
    /// Re-derives each row's conversation id from the daemon identity and the Agent session it names.
    private func migrate(_ rows: [TuiSessionSnapshot.Binding], identity: String) -> [TuiSessionSnapshot.Binding] {
        let parts = identity.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return rows }
        let identity = TuiResourceIdentity()
        var byAgent: [String: TuiSessionSnapshot.Binding] = [:]
        for row in rows {
            let id = identity.conversation(machine: parts[0], session: parts[1], provider: row.provider, providerSession: row.providerSession)
            guard id != row.id else { byAgent[id] = row; continue }
            let rebound = TuiSessionSnapshot.Binding(id: id, provider: row.provider, providerSession: row.providerSession, terminal: row.terminal, workspace: row.workspace,
                                                     surfaceID: row.surfaceID, workspaceID: row.workspaceID, title: row.title, cwd: row.cwd, state: row.state)
            // Two terminals that ran one Agent session collapse onto one conversation; the last write is the current one.
            byAgent[id] = rebound
        }
        return byAgent.values.sorted { $0.id < $1.id }
    }
    func save(identity: String, rows: [TuiSessionSnapshot.Binding]) throws {
        let data = try JSONEncoder().encode(Archive(identity: identity, rows: rows))
        guard rows.count <= 200, data.count <= 1_048_576 else { throw BridgeError("too_large", "The daemon conversation archive is full.", status: 413) }
        let staging = directory.appendingPathComponent(".tui-bindings-" + UUID().uuidString)
        let fd = Darwin.open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: staging) }
        try handle.write(contentsOf: data); try handle.synchronize()
        guard Darwin.rename(staging.path, path(identity).path) == 0 else { throw invalid() }
    }
    private func path(_ identity: String) -> URL {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("tui-bindings-" + hash + ".json")
    }
    private func invalid() -> BridgeError { BridgeError("invalid_state", "The private daemon binding archive is invalid.", status: 503) }
}
