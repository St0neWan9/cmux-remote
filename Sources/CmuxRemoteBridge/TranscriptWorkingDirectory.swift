import Foundation

/// The agent's own working directory, from the newest transcript record that states it.
/// A terminal's launch directory (often the home folder) is not where the agent works.
struct TranscriptWorkingDirectory: Sendable {
    func read(path: String, size: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let window = min(size, 131_072)
        guard (try? handle.seek(toOffset: UInt64(size - window))) != nil, let data = try? handle.read(upToCount: window) else { return nil }
        // The first line of the window may be partial; only complete lines are parsed.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst(window < size ? 1 : 0)
        for line in lines.reversed() where line.contains("\"cwd\"") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let cwd = object["cwd"] as? String ?? (object["payload"] as? [String: Any])?["cwd"] as? String
            if let cwd, cwd.hasPrefix("/"), cwd.utf8.count < 4096 { return cwd }
        }
        return nil
    }
}
