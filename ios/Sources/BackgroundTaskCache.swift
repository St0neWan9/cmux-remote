import Foundation
import CmuxRemoteCore

/// The last read of one background task, kept on the phone so reopening its page shows content at once.
///
/// It mirrors the conversation cache: the stored copy is shown first, and the read that follows either
/// confirms it or replaces it. A task's record is smaller than a conversation's, but a long command can still
/// exceed what is worth reopening instantly, so an oversized copy is simply not saved.
actor BackgroundTaskCache {
    private let directory: URL
    private let entryLimit = 4_194_304
    private let entryCount = 16
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BackgroundTasks", isDirectory: true)
    }
    struct Entry: Codable, Sendable {
        let snapshot: ConversationSnapshot?
        let text: String?
        let loadedBytes: Int
        let nextOffset: Int?
        let totalBytes: Int
        let running: Bool
        let storedAt: Date
    }
    func load(scope: String, sessionID: String, taskID: String) -> Entry? {
        let file = file(scope: scope, sessionID: sessionID, taskID: taskID)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? Int ?? 0) <= entryLimit else { return nil }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                guard bytes.count + chunk.count <= entryLimit else { return nil }
                bytes.append(chunk)
            }
            let entry = try JSONDecoder().decode(Entry.self, from: bytes)
            // Reading it is a use, so the copy survives the next eviction pass.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return entry
        } catch { return nil }
    }
    func save(_ entry: Entry, scope: String, sessionID: String, taskID: String) {
        let file = file(scope: scope, sessionID: sessionID, taskID: taskID)
        guard let bytes = try? JSONEncoder().encode(entry), bytes.count <= entryLimit else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard (try FileManager.default.attributesOfItem(atPath: directory.path))[.type] as? FileAttributeType == .typeDirectory else { return }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            prune()
        } catch {}
    }
    /// Drops the least recently used copies until the directory is within its bound.
    private func prune() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        guard entries.count > entryCount else { return }
        let dated = entries.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }.sorted { $0.1 < $1.1 }
        for (url, _) in dated.prefix(entries.count - entryCount) { try? FileManager.default.removeItem(at: url) }
    }
    private func file(scope: String, sessionID: String, taskID: String) -> URL {
        directory.appendingPathComponent(name(scope: scope, sessionID: sessionID, taskID: taskID))
    }
    /// A task is identified by all three, and none may escape the directory.
    private func name(scope: String, sessionID: String, taskID: String) -> String {
        let safe = { (value: String) in String(value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }) }
        return safe(scope) + "." + safe(sessionID) + "." + safe(taskID) + ".json"
    }
}
