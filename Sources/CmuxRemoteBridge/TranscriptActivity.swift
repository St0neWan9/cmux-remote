import Foundation

/// When the conversation last moved: the newest message record's own timestamp.
/// Agents append bookkeeping (mode, permission and title records) to idle sessions, so file write time overstates activity.
struct TranscriptActivity: Sendable {
    private static let messageTypes: Set<String> = ["user", "assistant", "response_item"]
    /// Large tool results can bury the last message, so a short tail widens once to a bounded 2 MiB.
    func lastMessage(path: String, size: Int) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        if let date = lastMessage(handle, size: size, window: min(size, 131_072)) { return date }
        return size > 131_072 ? lastMessage(handle, size: size, window: min(size, 2_097_152)) : nil
    }
    private func lastMessage(_ handle: FileHandle, size: Int, window: Int) -> Date? {
        guard (try? handle.seek(toOffset: UInt64(size - window))) != nil, let data = try? handle.read(upToCount: window) else { return nil }
        // The first line of the window may be partial; only complete lines are parsed.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst(window < size ? 1 : 0)
        for line in lines.reversed() where line.contains("\"timestamp\"") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = object["type"] as? String, Self.messageTypes.contains(type),
                  let stamp = object["timestamp"] as? String, let date = Self.date(stamp) else { continue }
            return date
        }
        return nil
    }
    private static func date(_ value: String) -> Date? {
        guard value.utf8.count <= 64 else { return nil }
        return (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(value, strategy: .iso8601))
    }
}
