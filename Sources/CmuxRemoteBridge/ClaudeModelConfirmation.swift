import Foundation
import CmuxRemoteCore

/// Settles the question Claude Code may ask right after a `/model` command.
///
/// Switching a long conversation to another model makes Claude Code stop at "Switch model?", because the whole
/// history is read again under the new model. The menu belongs to the reader who asked, so it is answered only as
/// they chose: with `confirm` the first option is taken, without it the menu is closed and the reader is told, and
/// nothing changes either way until they decide.
struct ClaudeModelConfirmation: Sendable {
    let attempts: Int
    let interval: Duration
    init(attempts: Int = 5, interval: Duration = .milliseconds(200)) {
        self.attempts = max(1, attempts); self.interval = interval
    }
    func settle(on console: AgentConsole, confirm: Bool) async throws {
        for attempt in 0..<attempts {
            if attempt > 0 { try await Task.sleep(for: interval) }
            guard AgentMenuScreen(rows: try await console.rows()).asksToConfirmModelSwitch else { continue }
            // One key per write: several arriving together are taken as a paste and ignored by the menu.
            try await console.write(confirm ? "1" : "\u{1b}", confirm ? "confirm" : "cancel")
            try await Task.sleep(for: interval)
            guard !AgentMenuScreen(rows: try await console.rows()).asksToConfirmModelSwitch else {
                throw BridgeError("outcome_unknown", "Claude Code did not close its model confirmation; inspect the Agent.", status: 409)
            }
            guard confirm else {
                throw BridgeError("model_confirm_required", "Claude Code asks to confirm this model switch; nothing changed.", status: 409)
            }
            return
        }
    }
}
