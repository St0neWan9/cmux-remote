import Foundation
import TermRemoteCore

/// Claude Code's own process registry: one owner metadata file per running
/// process, keyed by pid. It never contains conversation text, and it is only
/// consulted for a pid that a provider proves is the terminal's foreground.
public struct ClaudeProcessRegistry: Sendable {
    public struct Binding: Sendable, Equatable {
        public let pid: Int
        public let sessionID: String
        public let cwd: String
        public let status: String
        public let transcript: String

        /// The phone's conversation state for this registry status.
        ///
        /// Claude writes `shell` when its turn has finished but a background shell it started is
        /// still running; it is waiting for the person, so it is idle, not working. Only `busy`
        /// and statuses this Bridge does not know yet are reported as working.
        public var conversationState: String {
            switch status {
            case "idle", "shell": return "idle"
            default: return "working"
            }
        }
    }

    private struct Record: Decodable {
        let pid: Int
        let sessionId: String
        let cwd: String
        let status: String?
        let procStart: String?
    }

    private let home: URL

    public init(home: URL) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
    }

    /// A binding only when the registry file is a regular owner file, names the
    /// same pid, and the derived transcript exists under the configured roots.
    public func binding(pid: Int, cwd expectedCwd: String?, roots: [URL]) -> Binding? {
        guard pid > 0 else { return nil }
        let file = home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let data = try? Data(contentsOf: file), data.count <= 65_536,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.pid == pid, UUID(uuidString: record.sessionId) != nil,
              record.cwd.hasPrefix("/") else { return nil }
        if let expectedCwd, !expectedCwd.isEmpty {
            let actual = URL(fileURLWithPath: record.cwd).standardizedFileURL.path
            let expected = URL(fileURLWithPath: expectedCwd).standardizedFileURL.path
            guard actual == expected else { return nil }
        }
        let transcript = transcriptPath(cwd: record.cwd, sessionID: record.sessionId)
        // A long conversation is still a valid binding: history reads bounded windows, not the whole file.
        // The cap only rejects an implausible registry entry, not a real transcript.
        guard let values = try? URL(fileURLWithPath: transcript).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, size <= 1_073_741_824 else { return nil }
        let allowed = roots.contains { root in
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            return transcript.hasPrefix(resolved + "/")
        }
        guard allowed else { return nil }
        return Binding(pid: pid, sessionID: record.sessionId, cwd: record.cwd,
                       status: record.status ?? "unknown", transcript: transcript)
    }

    /// Claude names its project directory by replacing every non-alphanumeric
    /// character in the working directory with a dash. Verified against 16/16
    /// local sessions on 2026-11-19; a missing file means no binding.
    func transcriptPath(cwd: String, sessionID: String) -> String {
        let encoded = String(cwd.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
        return home.appendingPathComponent(".claude/projects/\(encoded)/\(sessionID).jsonl").path
    }
}
