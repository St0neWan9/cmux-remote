import Foundation
import TermRemoteCore
import TermRemoteBridge

/// The command an Agent hook runs inside a Rex terminal. It never writes a
/// prompt or transcript body: only ids, paths and the event name reach the spool.
struct AgentHookCommand {
    func run(options: CLIOptions, state: BridgeState) throws {
        guard let agent = options.value("agent"), ["claude", "codex", "antigravity"].contains(agent) else { return }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard input.count <= 1_048_576,
              let object = try? JSONDecoder().decode(JSONValue.self, from: input).object else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let block = environment["REX_BLOCK"], block.hasPrefix("block:"),
              let session = environment["REX_SESSION"], session.hasPrefix("session:"),
              let payloadSession = first(object, ["session_id", "sessionId", "thread_id", "threadId", "conversation_id", "conversationId"]),
              let rawTranscript = first(object, ["transcript_path", "transcriptPath", "rollout_path", "rolloutPath"]),
              let cwd = first(object, ["cwd", "workdir", "directory"]) ?? firstWorkspacePath(object), cwd.hasPrefix("/"),
              payloadSession.utf8.count <= 256, rawTranscript.utf8.count <= 4_096, block.utf8.count <= 256 else { return }
        let transcript = preferredTranscript(rawTranscript, agent: agent)
        let event = options.value("event") ?? first(object, ["hook_event_name", "hookEventName", "event"]) ?? "unknown"
        guard event.utf8.count <= 128 else { return }
        let record = RexHookRecord(agent: agent, event: event, sessionID: payloadSession, transcript: transcript,
                                   cwd: cwd, rexSession: session, rexBlock: block,
                                   rexServer: environment["REX_SERVER"])
        try RexHookWriter.write(record, directory: state.directory.appendingPathComponent("rex-hooks", isDirectory: true))
    }

    private func first(_ object: [String: JSONValue], _ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }

    private func firstWorkspacePath(_ object: [String: JSONValue]) -> String? {
        for key in ["workspacePaths", "workspace_paths"] {
            if let first = object[key]?.array?.first?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                return first
            }
        }
        return nil
    }

    private func preferredTranscript(_ path: String, agent: String) -> String {
        guard agent == "antigravity", path.hasSuffix("/transcript.jsonl") else { return path }
        let full = String(path.dropLast("transcript.jsonl".count)) + "transcript_full.jsonl"
        return FileManager.default.fileExists(atPath: full) ? full : path
    }
}
