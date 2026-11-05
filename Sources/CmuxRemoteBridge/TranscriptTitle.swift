import Foundation

/// The summary Claude writes for a conversation, used when cmux has no name for it.
struct TranscriptTitle: Sendable {
    /// The newest `ai-title` record: the agent rewrites it as the conversation develops.
    ///
    /// The record is written as the conversation develops, so it is looked for from the end of the file and the
    /// search widens only when the tail holds none. Reading the whole record instead cost a Mac with sixty
    /// conversations ten seconds on the first list read after a restart: one transcript alone is 78 MB, and every
    /// line of it was parsed to find a title that sat near the end.
    func readTitle(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path), let size = try? handle.seekToEnd(), size > 0 else { return nil }
        defer { try? handle.close() }
        var end = Int(size)
        var window = 262_144
        // A title that only exists at the very start of a very long record is worth less than the read it would
        // cost; the conversation keeps its first prompt as a name.
        let scanned = 8 * 1_048_576
        var read = 0
        while end > 0, read < scanned {
            let start = max(0, end - window)
            guard (try? handle.seek(toOffset: UInt64(start))) != nil, let data = try? handle.read(upToCount: end - start) else { return nil }
            read += data.count
            // The window's first line may be cut by its edge; only whole lines are read.
            let lines = data.split(separator: 10, omittingEmptySubsequences: false)
            for line in lines.reversed() where line.count <= 65_536 && line.starts(with: Self.marker) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                      object["type"] as? String == "ai-title", let value = object["aiTitle"] as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.utf8.count <= 8192 { return trimmed }
            }
            end = start
            window = min(window * 2, scanned)
        }
        return nil
    }
    private static let marker = Data(#"{"type":"ai-title""#.utf8)
}
