import Foundation
import TermRemoteCore
import TermRemoteBridge

/// The command an Agent hook runs inside a Rex terminal. It never writes a
/// prompt or transcript body: only ids, paths and the event name reach the spool.
struct AgentHookCommand {
    func run(options: CLIOptions, state: BridgeState) throws {
        guard let agent = options.value("agent"), ["claude", "codex"].contains(agent) else { return }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard input.count <= 1_048_576,
              let object = try? JSONDecoder().decode(JSONValue.self, from: input).object else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let block = environment["REX_BLOCK"], block.hasPrefix("block:"),
              let session = environment["REX_SESSION"], session.hasPrefix("session:"),
              let payloadSession = first(object, ["session_id", "sessionId", "thread_id", "threadId", "conversation_id", "conversationId"]),
              let transcript = first(object, ["transcript_path", "transcriptPath", "rollout_path", "rolloutPath"]),
              let cwd = first(object, ["cwd", "workdir", "directory"]), cwd.hasPrefix("/"),
              payloadSession.utf8.count <= 256, transcript.utf8.count <= 4_096, block.utf8.count <= 256 else { return }
        let event = options.value("event") ?? first(object, ["hook_event_name", "event"]) ?? "unknown"
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
}
