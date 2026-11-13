import Foundation

/// How a transcript begins: Claude Code opens the session `/clear` starts with that command, dated when it ran.
/// The old session's own file is left as it was, so the new one's opening is the only record of the clear.
struct TranscriptOpening: Sendable {
    /// The opening is in the first records, after a mode line, a file snapshot and the command's caveat.
    private static let window = 65_536
    /// When `/clear` opened this session: `.some(date)` it did, `.some(nil)` it did not, nil when the file does
    /// not tell yet (unreadable, or no message recorded so far), so the caller reads it again later.
    func clearedFrom(path: String) -> Date?? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.window), !data.isEmpty else { return nil }
        // The last line of a full window may be cut; only complete lines are parsed.
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if data.count == Self.window, data.last != 10 { lines = lines.dropLast() }
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            if (object["commandRun"] as? [String: Any])?["command"] as? String == "clear" { return .some(Self.date(object["timestamp"])) }
            guard type == "user" || type == "assistant" else { continue }
            if Self.text(object).contains("<command-name>/clear</command-name>") { return .some(Self.date(object["timestamp"])) }
            // The caveat Claude Code writes before a local command is not the conversation's first message.
            if object["isMeta"] as? Bool == true { continue }
            return .some(nil)
        }
        return data.count == Self.window ? .some(nil) : nil
    }
    private static func text(_ object: [String: Any]) -> String {
        let content = (object["message"] as? [String: Any])?["content"]
        if let text = content as? String { return text }
        return (content as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
    }
    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String, value.utf8.count <= 64 else { return nil }
        return (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(value, strategy: .iso8601))
    }
}
