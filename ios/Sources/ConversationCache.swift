import Foundation
import Darwin
import CmuxRemoteCore

/// The last read of a conversation, kept on the phone so opening a page shows its content at once.
///
/// The reads themselves are cheap to repeat but not free: each one is a round trip over the relay, and a
/// conversation that was read a moment ago is almost always unchanged. Showing the stored copy first means
/// the page is never blank, and the refresh that follows either confirms it or replaces it.
actor ConversationCache {
    private let directory: URL
    /// One conversation's copy; a page longer than this is not worth reopening instantly.
    private let entryLimit = 4_194_304
    /// Conversations kept before the least recently used are dropped.
    private let entryCount = 24
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Conversations")
    }
    /// What was read last: the history page and the live tail, as the model holds them.
    struct Entry: Codable, Sendable {
        let snapshot: ConversationSnapshot
        let preview: PreviewSnapshot?
        let storedAt: Date
    }
    func load(scope: String, sessionID: String) -> Entry? {
        let file = file(scope: scope, sessionID: sessionID)
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
    /// When a conversation was last written, without reading it. An atomic save replaces the file, so its
    /// creation date is the write; the modification date also moves when the copy is merely opened.
    func storedAt(scope: String, sessionID: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file(scope: scope, sessionID: sessionID).path))?[.creationDate] as? Date
    }
    func save(_ entry: Entry, scope: String, sessionID: String) {
        let file = file(scope: scope, sessionID: sessionID)
        guard let bytes = try? JSONEncoder().encode(entry), bytes.count <= entryLimit else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard (try FileManager.default.attributesOfItem(atPath: directory.path))[.type] as? FileAttributeType == .typeDirectory else { return }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            prune()
        } catch {}
    }
    func remove(scope: String) {
        let prefix = name(scope: scope, sessionID: "")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) { try? FileManager.default.removeItem(at: entry) }
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
    private func file(scope: String, sessionID: String) -> URL { directory.appendingPathComponent(name(scope: scope, sessionID: sessionID)) }
    /// A conversation is identified by both, and neither may escape the directory.
    private func name(scope: String, sessionID: String) -> String {
        let safe = { (value: String) in String(value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }) }
        return safe(scope) + "." + safe(sessionID) + (sessionID.isEmpty ? "" : ".json")
    }
}
