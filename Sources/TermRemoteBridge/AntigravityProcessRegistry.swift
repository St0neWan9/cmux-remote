import Foundation
import Darwin
import SQLite3
import TermRemoteCore

/// Antigravity CLI's own local presence proof: every running `agy` process holds an open
/// lock file at `<root>/presence/<conversation-id>.lock`. Consulted only for a foreground pid
/// proved by a local terminal provider; never guesses by cwd, title or time.
public struct AntigravityProcessRegistry: Sendable {
    public struct Binding: Sendable, Equatable {
        public let pid: Int
        public let sessionID: String
        public let cwd: String
        public let title: String?
        public let status: String
        public let transcript: String
        public let transcriptExists: Bool

        /// The phone's conversation state for Antigravity's summary status.
        public var conversationState: String {
            switch status {
            case "CASCADE_RUN_STATUS_RUNNING": return "working"
            case "CASCADE_RUN_STATUS_WAITING_FOR_USER": return "needs_input"
            default: return "idle"
            }
        }
    }

    public struct Metadata: Sendable, Equatable {
        public let title: String?
        public let status: String
        public let workspacePaths: [String]
    }

    private let root: URL
    private let openFiles: @Sendable (Int) -> [String]

    public init(home: URL, root: URL? = nil, openFiles: (@Sendable (Int) -> [String])? = nil) {
        let defaultRoot = home.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
        self.root = (root ?? defaultRoot).resolvingSymlinksInPath().standardizedFileURL
        self.openFiles = openFiles ?? Self.processOpenFiles
    }

    public init(root: URL, openFiles: (@Sendable (Int) -> [String])? = nil) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.openFiles = openFiles ?? Self.processOpenFiles
    }

    /// A binding only when `pid` holds an open regular file at `<root>/presence/<uuid>.lock`
    /// and its derived transcript path stays strictly under the configured roots.
    public func binding(pid: Int, cwd expectedCwd: String?, roots: [URL]) -> Binding? {
        guard pid > 0 else { return nil }
        let presenceDir = root.appendingPathComponent("presence", isDirectory: true).path
        guard let sessionID = lockedSessionID(pid: pid, presenceDirectory: presenceDir) else { return nil }

        let meta = metadata(sessionID: sessionID)
        let resolvedCwd: String
        if let expectedCwd, !expectedCwd.isEmpty, expectedCwd.hasPrefix("/") {
            let expected = URL(fileURLWithPath: expectedCwd).resolvingSymlinksInPath().standardizedFileURL.path
            if let paths = meta?.workspacePaths, !paths.isEmpty {
                let standardized = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
                guard standardized.contains(expected) else { return nil }
                resolvedCwd = expected
            } else {
                resolvedCwd = expected
            }
        } else if let first = meta?.workspacePaths.first, first.hasPrefix("/") {
            resolvedCwd = URL(fileURLWithPath: first).resolvingSymlinksInPath().standardizedFileURL.path
        } else {
            return nil
        }

        guard let resolved = resolveTranscript(sessionID: sessionID, roots: roots) else { return nil }
        return Binding(
            pid: pid,
            sessionID: sessionID,
            cwd: resolvedCwd,
            title: meta?.title,
            status: meta?.status ?? "CASCADE_RUN_STATUS_IDLE",
            transcript: resolved.path,
            transcriptExists: resolved.exists
        )
    }

    /// Reads Antigravity's recorded title, run status and workspace directories for one session id,
    /// consulting `conversation_summaries.db` (read-only) first and falling back to `cache/conversation_metadata.json`.
    public func metadata(sessionID: String) -> Metadata? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let normalized = sessionID.lowercased()
        if let fromDB = readSQLiteMetadata(sessionID: normalized) { return fromDB }
        return readJSONMetadata(sessionID: normalized)
    }

    /// Resolves the canonical transcript path for `sessionID`, preferring `transcript_full.jsonl` over `transcript.jsonl`.
    public func resolveTranscript(sessionID: String, roots: [URL]) -> (path: String, exists: Bool)? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let logs = root
            .appendingPathComponent("brain", isDirectory: true)
            .appendingPathComponent(sessionID.lowercased(), isDirectory: true)
            .appendingPathComponent(".system_generated", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        let full = logs.appendingPathComponent("transcript_full.jsonl")
        let compact = logs.appendingPathComponent("transcript.jsonl")

        for candidate in [full, compact] {
            if let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
               values.isRegularFile == true, values.isSymbolicLink != true,
               let size = values.fileSize, size >= 0, size <= 1_073_741_824 {
                let path = candidate.resolvingSymlinksInPath().standardizedFileURL.path
                guard isAllowed(path: path, roots: roots) else { return nil }
                return (path, true)
            }
        }

        // Brand-new session before its first prompt: allow pending path under an allowed root.
        let pendingPath = full.standardizedFileURL.path
        guard isAllowed(path: pendingPath, roots: roots) else { return nil }
        return (pendingPath, false)
    }

    private func lockedSessionID(pid: Int, presenceDirectory: String) -> String? {
        let prefix = presenceDirectory + "/"
        for rawPath in openFiles(pid) {
            let standardized = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL.path
            guard standardized.hasPrefix(prefix), standardized.hasSuffix(".lock") else { continue }
            let relative = String(standardized.dropFirst(prefix.count))
            guard !relative.contains("/") else { continue }
            let candidate = String(relative.dropLast(5))
            guard UUID(uuidString: candidate) != nil else { continue }
            let url = URL(fileURLWithPath: standardized)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            return candidate.lowercased()
        }
        return nil
    }

    private func isAllowed(path: String, roots: [URL]) -> Bool {
        roots.contains { candidateRoot in
            let resolved = candidateRoot.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(resolved + "/")
        }
    }

    private func readSQLiteMetadata(sessionID: String) -> Metadata? {
        let dbURL = root.appendingPathComponent("conversation_summaries.db")
        guard let values = try? dbURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        var statement: OpaquePointer?
        let sql = "SELECT title, status, workspace_uris FROM conversation_summaries WHERE conversation_id = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, sessionID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let rawTitle = sqlite3_column_text(statement, 0).map { String(cString: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(512)) }
        let status = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "CASCADE_RUN_STATUS_IDLE"
        let rawURIs = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let paths = Self.parseWorkspaceURIs(rawURIs)
        return Metadata(title: title, status: status, workspacePaths: paths)
    }

    private func readJSONMetadata(sessionID: String) -> Metadata? {
        let file = root.appendingPathComponent("cache/conversation_metadata.json")
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4_194_304,
              let data = try? Data(contentsOf: file), data.count <= 4_194_304,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let conversations = json["conversations"] as? [String: Any],
              let entry = (conversations[sessionID] ?? conversations[sessionID.uppercased()]) as? [String: Any],
              let summary = entry["summary"] as? [String: Any] else { return nil }
        let rawTitle = (summary["Title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(512)) }
        let rawURIs = summary["WorkspaceURIs"] as? [String] ?? []
        let paths = rawURIs.compactMap(Self.fileURIPath)
        return Metadata(title: title, status: "CASCADE_RUN_STATUS_IDLE", workspacePaths: paths)
    }

    static func parseWorkspaceURIs(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let uris = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return [] }
        return uris.compactMap(fileURIPath)
    }

    private static func fileURIPath(_ uri: String) -> String? {
        if uri.hasPrefix("file://"), let url = URL(string: uri), url.isFileURL, url.path.hasPrefix("/") {
            return url.path
        }
        return uri.hasPrefix("/") ? uri : nil
    }

    /// Reads the regular file paths currently held open by `pid` using Darwin `libproc`, bounded to 4096 FDs.
    private static func processOpenFiles(_ pid: Int) -> [String] {
        #if os(macOS)
        let target = pid_t(pid)
        let bytesNeeded = proc_pidinfo(target, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        let count = min(Int(bytesNeeded) / stride, 4096)
        guard count > 0 else { return [] }
        var fds = Array(repeating: proc_fdinfo(), count: count)
        let actualBytes = fds.withUnsafeMutableBytes { buffer in
            proc_pidinfo(target, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard actualBytes > 0 else { return [] }
        let used = min(count, Int(actualBytes) / stride)
        var paths: [String] = []
        let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
        for index in 0..<used {
            let fd = fds[index]
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { continue }
            var info = vnode_fdinfowithpath()
            let read = withUnsafeMutableBytes(of: &info) { buffer in
                proc_pidfdinfo(target, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, buffer.baseAddress, infoSize)
            }
            guard read == infoSize else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw -> String? in
                guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return nil }
                return String(cString: base)
            }
            if let path, path.hasPrefix("/") { paths.append(path) }
        }
        return paths
        #else
        return []
        #endif
    }
}
