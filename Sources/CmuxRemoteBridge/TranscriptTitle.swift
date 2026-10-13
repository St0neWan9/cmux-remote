import Foundation

/// The summary Claude writes for a conversation, used when cmux has no name for it.
struct TranscriptTitle: Sendable {
    /// The newest `ai-title` record: the agent rewrites it as the conversation develops.
    func readTitle(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var title: String?
        while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
            for line in data.split(separator: 10) where line.count <= 65_536 {
                guard line.starts(with: Self.marker), let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                      object["type"] as? String == "ai-title", let value = object["aiTitle"] as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.utf8.count <= 8192 { title = trimmed }
            }
        }
        return title
    }
    private static let marker = Data(#"{"type":"ai-title""#.utf8)
}
