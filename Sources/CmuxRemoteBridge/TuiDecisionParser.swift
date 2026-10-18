import Foundation
import CmuxRemoteCore

/// Recognizes the runtime dialogs an Agent blocks on: the standard command permission layouts, the plan
/// approval, Claude Code's AskUserQuestion menu for the request its transcript recorded, and the plain
/// "press enter to continue · esc to cancel" notice. Never generic numeric-key approval, and never a dialog
/// whose layout is not exactly one of these.
struct TuiDecisionParser: Sendable {
    /// `ask` is the AskUserQuestion the Agent's transcript has pending, if any; only its own menu is offered.
    func permission(snapshot: TuiSessionSnapshot, binding: TuiSessionSnapshot.Binding, screen: JSONValue, ask: AskUserQuestionRequest? = nil) -> TuiPendingDecision? {
        guard binding.state == "needs_input", let text = screen["text"].string, text.utf8.count <= 32_768,
              let outputRevision = screen["revision"].string, UInt64(outputRevision) != nil else { return nil }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let identity = TuiResourceIdentity().uuid(machine: snapshot.machine, session: snapshot.session,
            resource: binding.id + ":" + snapshot.generation + ":" + outputRevision + ":" + text + (ask.map { ":" + $0.toolUseID } ?? ""))
        let id = "tui-decision:" + identity
        let keys: [String]
        if binding.provider == "claude", lines.contains("Do you want to proceed?"),
           lines.contains("❯ 1. Yes") || lines.contains("❯\u{00a0}1. Yes"),
           lines.contains(where: { $0 == "3. No" || $0.hasPrefix("3. No, ") }),
           lines.suffix(6).contains(where: { $0.lowercased().contains("esc to cancel") }) {
            keys = ["enter"]
        } else if binding.provider == "codex", lines.contains("Would you like to run the following command?"),
                  lines.contains(where: { $0 == "› 1. Yes, proceed (y)" || $0 == "❯ 1. Yes, proceed (y)" }),
                  lines.contains(where: { $0.hasPrefix("3. No") && $0.contains("(esc)") }) {
            keys = ["y"]
        } else if binding.provider == "claude", let ask, ask.isFreshMenu(lines) {
            return TuiPendingDecision(id: id, binding: binding, generation: snapshot.generation, revision: snapshot.revision,
                                      screenRevision: outputRevision, screenText: text, allowKeys: [], kind: .question, ask: ask)
        } else if let notice = Self.continueNotice(lines) {
            // A notice that only waits for Enter or Escape: two choices, no permission granted.
            return TuiPendingDecision(id: id, binding: binding, generation: snapshot.generation, revision: snapshot.revision,
                                      screenRevision: outputRevision, screenText: text, allowKeys: ["enter", "escape"],
                                      kind: .question, choices: notice)
        } else { return nil }
        return TuiPendingDecision(id: id, binding: binding, generation: snapshot.generation, revision: snapshot.revision,
                                  screenRevision: outputRevision, screenText: text, allowKeys: keys)
    }
    /// The two choices a "press enter to continue" footer offers, when that footer is the whole dialog.
    ///
    /// The hints are matched on the screen's last rows and the wording is not taken from them: the labels stay
    /// fixed so a screen line cannot become a button. A permission layout is matched first, so this never
    /// turns one of those into a question.
    private static func continueNotice(_ lines: [String]) -> [(label: String, key: String)]? {
        let tail = lines.suffix(6).map { $0.lowercased() }
        let continues = tail.contains { $0.contains("enter to continue") || $0.contains("press enter to continue") || $0.contains("enter to confirm") }
        guard continues, tail.contains(where: { $0.contains("esc to cancel") || $0.contains("esc to go back") }) else { return nil }
        return [(label: "继续", key: "enter"), (label: "取消", key: "escape")]
    }
}
