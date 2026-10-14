import Foundation
import CmuxRemoteCore

/// Claude Code activity per provider session, folded from the daemon's agent hook journal.
/// The daemon's own state drops a running turn on a failed tool or a compaction; the raw hook names keep it.
struct TuiHookStates: Sendable {
    private(set) var states: [String: String] = [:]
    /// Applies one `agent.*` journal item; items from other providers or without a session leave the states unchanged.
    mutating func apply(_ item: JSONValue) {
        let payload = item["payload"]
        guard payload["adapter"]["id"].string == "claude", let native = payload["native_event"].string,
              let session = payload["normalized"]["agent_session_id"].string, UUID(uuidString: session) != nil else { return }
        let key = session.lowercased()
        switch Self.state(native: native, tool: payload["normalized"]["tool_name"].string, notification: payload["native"]["notification_type"].string, source: payload["native"]["source"].string) {
        case .some(.some(let state)):
            if states[key] == nil, states.count >= 1_024 { states.removeAll() }
            states[key] = state
        case .some(.none): states[key] = nil
        case .none: break
        }
    }
    /// A phone interrupt ends the turn; Claude Code reports no hook for an interrupt.
    mutating func interrupted(_ session: String) { if states[session.lowercased()] != nil { states[session.lowercased()] = "idle" } }
    /// The state a hook implies: nil keeps the current state, `.some(nil)` forgets the session.
    static func state(native: String, tool: String?, notification: String?, source: String?) -> String?? {
        switch native {
        case "PreToolUse": return ["AskUserQuestion", "ExitPlanMode"].contains(tool ?? "") ? "needs_input" : "working"
        case "UserPromptSubmit", "UserPromptExpansion", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
             "SubagentStart", "SubagentStop", "PreCompact", "PostCompact", "ElicitationResult": return "working"
        case "PermissionRequest", "Elicitation": return "needs_input"
        case "Notification":
            switch notification { case "permission_prompt": return "needs_input"; case "idle_prompt": return "idle"; default: return nil }
        case "Stop", "StopFailure": return "idle"
        // A compaction restarts the session inside a running turn.
        case "SessionStart": return source == "compact" ? nil : "idle"
        case "SessionEnd": return .some(nil)
        default: return nil
        }
    }
}
