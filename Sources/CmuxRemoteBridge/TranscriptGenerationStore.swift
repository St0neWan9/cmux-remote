import Foundation
import Darwin
import CmuxRemoteCore

/// A generation per transcript path that survives Bridge restarts but not record replacement.
///
/// A transcript's generation is replaced only when its inode or creation date changes, or when it
/// shrinks. Growing the record, moving the bounded history window, or restarting the Bridge keeps
/// the generation, so an archive cursor issued before any of those still names the same records.
/// Entries are bounded to 1024 paths and the file to 256 KiB; the least recently used entries are
/// dropped first. The file is written owner-only beside the Bridge's other private state.
public actor TranscriptGenerationStore {
    private struct Entry: Codable, Sendable {
        var inode: String
        var creationDate: Double?
        var sizeAtFirstRead: Int
        var generation: String
        var used: Int
    }
    private struct Document: Codable, Sendable { var entries: [String: Entry] }

    private static let capacity = 1024
    private static let fileSizeLimit = 262_144
    private static let fileName = "transcript-generations.json"
    private let directory: URL?
    private var entries: [String: Entry] = [:]
    private var sequence = 0
    private var loaded = false

    /// - Parameter directory: The Bridge state directory. Passing nil keeps generations only in
    ///   memory, which tests and fixtures use; production passes the Bridge state directory.
    public init(directory: URL?) { self.directory = directory }

    /// The stable generation for this record, creating or replacing one when its identity changed.
    public func generation(for path: String, inode: String, creationDate: Date?, size: Int) async -> String {
        loadIfNeeded()
        sequence += 1
        let stamp = creationDate?.timeIntervalSinceReferenceDate
        if var entry = entries[path] {
            let replaced = entry.inode != inode || !sameInstant(entry.creationDate, stamp) || size < entry.sizeAtFirstRead
            if replaced {
                entry = Entry(inode: inode, creationDate: stamp, sizeAtFirstRead: max(0, size), generation: UUID().uuidString, used: sequence)
                entries[path] = entry
                saveIfNeeded()
            } else {
                // Keep the generation while the record only grows; remember the watermark so a later
                // shrink below anything this generation already covered is still detected. The LRU
                // stamp changes on every read, so it alone does not rewrite the file.
                let grew = size > entry.sizeAtFirstRead
                entry.sizeAtFirstRead = max(entry.sizeAtFirstRead, size)
                entry.used = sequence
                entries[path] = entry
                if grew { saveIfNeeded() }
            }
            return entry.generation
        }
        let entry = Entry(inode: inode, creationDate: stamp, sizeAtFirstRead: max(0, size), generation: UUID().uuidString, used: sequence)
        entries[path] = entry
        trimToCapacity()
        saveIfNeeded()
        return entry.generation
    }

    /// The generation already recorded for this path, without creating or touching one.
    public func cachedGeneration(for path: String) -> String? {
        loadIfNeeded()
        return entries[path]?.generation
    }

    /// Whether a persisted generation exists at all, so tests can tell a restart from a fresh store.
    public func contains(path: String) -> Bool {
        loadIfNeeded()
        return entries[path] != nil
    }

    private func sameInstant(_ left: Double?, _ right: Double?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case let (left?, right?): return abs(left - right) < 0.001
        default: return false
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let directory, let data = readPrivateFile(directory.appendingPathComponent(Self.fileName)) else { return }
        guard data.count <= Self.fileSizeLimit, let document = try? JSONDecoder().decode(Document.self, from: data) else { return }
        entries = document.entries.filter { _, entry in
            !entry.generation.isEmpty && entry.generation.utf8.count <= 128 && entry.inode.utf8.count <= 128 && entry.sizeAtFirstRead >= 0
        }
        sequence = entries.values.map(\.used).max() ?? 0
        trimToCapacity()
    }

    /// The file is read only when it is a regular file owned by this user with no group/other bits.
    private func readPrivateFile(_ file: URL) -> Data? {
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= Self.fileSizeLimit else { return nil }
        return try? Data(contentsOf: file)
    }

    private func trimToCapacity() {
        guard entries.count > Self.capacity else { return }
        let oldest = entries.sorted { $0.value.used < $1.value.used }.prefix(entries.count - Self.capacity)
        for (path, _) in oldest { entries[path] = nil }
    }

    private func saveIfNeeded() {
        guard let directory else { return }
        trimToCapacity()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(Document(entries: entries)) else { return }
        // Paths can be long; drop the least recently used entries until the document fits. A single
        // entry that still does not fit is left only in memory.
        while data.count > Self.fileSizeLimit, !entries.isEmpty,
              let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            entries[oldest] = nil
            data = (try? encoder.encode(Document(entries: entries))) ?? Data()
        }
        guard data.count <= Self.fileSizeLimit else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let temporary = directory.appendingPathComponent(".transcript-generations-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let destination = directory.appendingPathComponent(Self.fileName)
            guard Darwin.rename(temporary.path, destination.path) == 0 else { return }
        } catch { return }
    }
}
