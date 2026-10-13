import Foundation
import CmuxRemoteCore

/// Only two recognized runtime permission layouts; never generic numeric-key approval.
struct TuiDecisionParser: Sendable {
    func permission(snapshot: TuiSessionSnapshot, binding: TuiSessionSnapshot.Binding, screen: JSONValue) -> TuiPendingDecision? {
        guard binding.state == "needs_input", let text = screen["text"].string, text.utf8.count <= 32_768,
              let outputRevision = screen["revision"].string, UInt64(outputRevision) != nil else { return nil }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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
        } else { return nil }
        let identity = TuiResourceIdentity().uuid(machine: snapshot.machine, session: snapshot.session,
            resource: "permission:" + binding.id + ":" + snapshot.generation + ":" + outputRevision + ":" + text)
        return TuiPendingDecision(id: "tui-decision:" + identity, binding: binding, generation: snapshot.generation, revision: snapshot.revision,
                                  screenRevision: outputRevision, screenText: text, allowKeys: keys)
    }
}
