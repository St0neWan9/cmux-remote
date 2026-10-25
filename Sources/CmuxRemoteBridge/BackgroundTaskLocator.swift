import Foundation
import CmuxRemoteCore

/// Finds what a background task produced inside the agent's own files.
///
/// An asynchronous Agent records its conversation under the session's `subagents/` sidecar, which names the
/// tool call that started it. A detached command's output lives in the agent's task directory for the session.
/// Both layouts belong to the local agent installation, so every lookup is a probe: a missing file is answered
/// as "no content", never as a failure of the session itself.
public struct BackgroundTaskLocator: Sendable {
    public struct Location: Sendable, Equatable {
        public let kind: BackgroundTaskContent.Kind
        public let path: String
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
        if let runtime = runtimeTaskID(transcript: transcript, toolUseID: taskID) { candidates.insert(directory.appendingPathComponent(runtime + ".output"), at: 0) }
        let root = URL(fileURLWithPath: temporaryRoot).resolvingSymlinksInPath().path + "/"
        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            // An Agent task's own record is reached through its sidecar above; a symlink here would leave the session.
            let resolved = file.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root) else { continue }
            return resolved.path
        }
        return nil
    }
    /// The id a launch result reports, read from the record's own tail: the result line names the tool call.
    private func runtimeTaskID(transcript: String, toolUseID: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: transcript)) else { return nil }
        defer { try? handle.close() }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: transcript)[.size] as? NSNumber)?.intValue else { return nil }
        let window = 4 * 1_048_576
        guard (try? handle.seek(toOffset: UInt64(max(0, size - window)))) != nil,
              let data = try? handle.read(upToCount: window) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let call = text.range(of: "\"tool_use_id\":\"" + toolUseID + "\"") ?? text.range(of: "\"tool_use_id\": \"" + toolUseID + "\"") else { return nil }
        let after = text[call.upperBound...].prefix(4_096)
        guard let marker = after.range(of: "Command running in background with ID: ") else { return nil }
        let id = after[marker.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return id.isEmpty ? nil : String(id)
    }
}
