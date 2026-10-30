import Foundation
import CmuxRemoteCore

/// Finds what a background task produced inside the agent's own files.
///
/// An asynchronous Agent records its conversation under the session's `subagents/` sidecar, which names the
/// tool call that started it. A detached command's output lives in the agent's task directory for the session.
/// Both layouts belong to the local agent installation, so every lookup is a probe: a missing file is answered
/// as "no content", never as a failure of the session itself.
public struct BackgroundTaskLocator: Sendable {
    /// The id one tool call runs under, remembered per record; a miss costs a stream of the record, so the
    /// answer is kept for the life of the reader.
    private final class RuntimeIDs: @unchecked Sendable {
        private let lock = NSLock(); private var values: [String: String] = [:]
        func get(_ key: String) -> String? { lock.withLock { values[key] } }
        func set(_ key: String, _ value: String) { lock.withLock { if values.count < 4_096 { values[key] = value } } }
    }
    private let runtimeIDs = RuntimeIDs()
    public struct Location: Sendable, Equatable {
        /// What the file holds: a command's raw output, or a Workflow's own journal, which is rendered for the
        /// phone instead of being shown as the JSON lines it is stored as.
        public enum Format: Sendable, Equatable { case raw, workflowJournal }
        public let kind: BackgroundTaskContent.Kind
        public let path: String
        public var format: Format = .raw
        public init(kind: BackgroundTaskContent.Kind, path: String, format: Format = .raw) {
            self.kind = kind; self.path = path; self.format = format
        }
    }
    /// The agent's own task directory root, `/tmp/claude-<uid>`.
    private let temporaryRoot: String
    public init(temporaryRoot: String = "/tmp/claude-\(getuid())") { self.temporaryRoot = temporaryRoot }

    /// A task id is a tool call id or an agent task id: an identifier, never a path.
    public static func isValid(_ taskID: String) -> Bool {
        !taskID.isEmpty && taskID.count <= 64 && taskID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public func locate(transcript: String, taskID: String) -> Location? {
        guard Self.isValid(taskID) else { return nil }
        let session = URL(fileURLWithPath: transcript).deletingPathExtension()
        if let agent = agentTranscript(session: session, taskID: taskID) { return Location(kind: .agent, path: agent) }
        // A Workflow names a transcript directory, and its own `.output` file stays empty: the run is in the journal.
        if let journal = workflowJournal(transcript: transcript, toolUseID: taskID) {
            return Location(kind: .output, path: journal, format: .workflowJournal)
        }
        if let output = outputFile(transcript: transcript, taskID: taskID) { return Location(kind: .output, path: output) }
        return nil
    }

    /// The sidecar next to the session's own record names the tool call, and its transcript sits beside it.
    private func agentTranscript(session: URL, taskID: String) -> String? {
        let directory = session.appendingPathComponent("subagents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        for name in names where name.hasSuffix(".meta.json") {
            let meta = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: meta), data.count <= 16_384,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["toolUseId"] as? String == taskID else { continue }
            // `agent-<id>.meta.json` describes `agent-<id>.jsonl`.
            let transcript = directory.appendingPathComponent(String(name.dropLast(".meta.json".count)) + ".jsonl")
            guard FileManager.default.fileExists(atPath: transcript.path) else { continue }
            return transcript.path
        }
        return nil
    }

    /// `/tmp/claude-<uid>/<project>/<session>/tasks/<task>.output`, where the project directory keeps the
    /// transcript's own directory name. A detached command names its file with the task id its launch result
    /// reports, not with the tool call that started it.
    private func outputFile(transcript: String, taskID: String) -> String? {
        let session = URL(fileURLWithPath: transcript).deletingPathExtension()
        let project = session.deletingLastPathComponent().lastPathComponent
        let directory = URL(fileURLWithPath: temporaryRoot)
            .appendingPathComponent(project)
            .appendingPathComponent(session.lastPathComponent)
            .appendingPathComponent("tasks")
        var candidates = [directory.appendingPathComponent(taskID + ".output")]
        let key = transcript + "\u{0}" + taskID
        let runtime = runtimeIDs.get(key) ?? runtimeTaskID(transcript: transcript, toolUseID: taskID)
        if let runtime { runtimeIDs.set(key, runtime); candidates.insert(directory.appendingPathComponent(runtime + ".output"), at: 0) }
        let root = URL(fileURLWithPath: temporaryRoot).resolvingSymlinksInPath().path + "/"
        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            // An Agent task's own record is reached through its sidecar above; a symlink here would leave the session.
            let resolved = file.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root) else { continue }
            return resolved.path
        }
        return nil
    }
    /// `<session>/workflows` holds every run of the workflows session; the launch result names this call's own
    /// directory, and the journal inside it is what the run actually did.
    private func workflowJournal(transcript: String, toolUseID: String) -> String? {
        let key = transcript + "\u{0}wf\u{0}" + toolUseID
        if let cached = runtimeIDs.get(key) { return cached }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: transcript)) else { return nil }
        defer { try? handle.close() }
        var pending = Data()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            pending.append(chunk)
            while let end = pending.lastIndex(of: 10) {
                let line = pending[pending.startIndex...end]
                pending.removeSubrange(pending.startIndex...end)
                guard let text = String(data: line, encoding: .utf8), text.contains(toolUseID),
                      let marker = text.range(of: "Transcript dir: ") else { continue }
                let raw = text[marker.upperBound...].prefix { !$0.isWhitespace && $0 != "\\" && $0 != "\"" }
                guard !raw.isEmpty else { continue }
                let journal = URL(fileURLWithPath: String(raw)).appendingPathComponent("journal.jsonl")
                guard FileManager.default.fileExists(atPath: journal.path) else { continue }
                runtimeIDs.set(key, journal.path)
                return journal.path
            }
        }
        return nil
    }
    /// The command a tool call ran, when the record keeps it; the phone shows it above the output.
    public func launchCommand(transcript: String, toolUseID: String) -> String? {
        guard Self.isValid(toolUseID) else { return nil }
        let key = transcript + "\u{0}cmd\u{0}" + toolUseID
        if let cached = runtimeIDs.get(key) { return cached }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: transcript)) else { return nil }
        defer { try? handle.close() }
        var pending = Data()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            pending.append(chunk)
            while let end = pending.lastIndex(of: 10) {
                let line = pending[pending.startIndex...end]
                pending.removeSubrange(pending.startIndex...end)
                guard let text = String(data: line, encoding: .utf8), text.contains(toolUseID), text.contains("\"tool_use\"") else { continue }
                guard let data = text.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = (root["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
                for block in content where block["type"] as? String == "tool_use" && block["id"] as? String == toolUseID {
                    guard let input = block["input"] as? [String: Any] else { continue }
                    let command = (input["command"] as? String) ?? (input["script"] as? String) ?? (input["file_path"] as? String)
                    guard let command else { continue }
                    let bounded = String(command.prefix(16_384))
                    runtimeIDs.set(key, bounded)
                    return bounded
                }
            }
        }
        return nil
    }
    /// The id a launch result reports, read from the record: only the result's own row names the id the task
    /// runs under, and a task started long ago may sit far above the newest pages, so the whole record is
    /// streamed once and the scan stops at the first row that names it.
    private func runtimeTaskID(transcript: String, toolUseID: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: transcript)) else { return nil }
        defer { try? handle.close() }
        var pending = Data()
        var scanned = 0
        let limit = 268_435_456
        while scanned < limit, let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            scanned += chunk.count
            pending.append(chunk)
            // A row is only read when its newline has arrived; the unfinished tail is kept for the next chunk.
            while let end = pending.lastIndex(of: 10) {
                let line = pending[pending.startIndex...end]
                pending.removeSubrange(pending.startIndex...end)
                guard let text = String(data: line, encoding: .utf8), text.contains(toolUseID) else { continue }
                guard let marker = text.range(of: "Command running in background with ID: ") else { continue }
                let id = text[marker.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
                if !id.isEmpty { return String(id) }
            }
        }
        return nil
    }
}
