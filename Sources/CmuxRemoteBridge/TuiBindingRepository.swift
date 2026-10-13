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
        guard archive.identity == identity, archive.rows.count <= 200, Set(archive.rows.map(\.id)).count == archive.rows.count,
              archive.rows.allSatisfy({ $0.id.hasPrefix("tui:") && UUID(uuidString: $0.providerSession) != nil && ["claude", "codex"].contains($0.provider) && $0.title.utf8.count <= 8192 && ($0.cwd?.utf8.count ?? 0) <= 8192 }) else { throw invalid() }
        return archive.rows
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
