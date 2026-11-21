import Foundation
import TermRemoteCore

/// The model a transcript last reported, from the records each agent writes about it.
///
/// Claude Code names the model on every reply and prints `Set model to …` when the reader switches; a subagent's
/// replies run on their own model, so sidechain records are skipped. Codex names model and effort in the
/// `turn_context` that opens each turn. Antigravity names the model on each `PLANNER_RESPONSE`.
struct TranscriptModelReader {
    func read(lines: [String], agent: String) -> AgentModelState? {
        var latest: AgentModelState?
        for line in lines {
            // Every refresh walks the window, so a substring test keeps the JSON parse for the rows that can carry a model.
            if agent == "claude" {
                guard line.contains("\"model\":\"") || line.contains("model to `") || line.contains("model as `") else { continue }
            } else if agent == "antigravity" {
                guard line.contains("\"PLANNER_RESPONSE\"") && line.contains("\"model\"") else { continue }
            } else {
                guard line.contains("\"turn_context\"") else { continue }
            }
            guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let found: AgentModelState?
            switch agent {
            case "claude": found = claude(value)
            case "antigravity": found = antigravity(value)
            default: found = codex(value)
            }
            if let found { latest = found }
        }
        return latest
    }
    private func claude(_ value: [String: Any]) -> AgentModelState? {
        guard value["isSidechain"] as? Bool != true else { return nil }
        let message = value["message"] as? [String: Any]
        if value["type"] as? String == "assistant" {
            guard let model = message?["model"] as? String, let name = Self.bounded(model), !name.hasPrefix("<") else { return nil }
            return AgentModelState(model: name)
        }
        // A switch is recorded as the command's own output, as a user row or a system row depending on the version.
        let content = (message?["content"] as? String) ?? (value["content"] as? String) ?? ""
        guard content.hasPrefix("<local-command-stdout>") else { return nil }
        for marker in ["Set model to `", "Kept model as `"] {
            guard let start = content.range(of: marker), let end = content[start.upperBound...].firstIndex(of: "`") else { continue }
            return Self.bounded(String(content[start.upperBound..<end])).map { AgentModelState(model: $0) }
        }
        return nil
    }
    private func codex(_ value: [String: Any]) -> AgentModelState? {
        guard value["type"] as? String == "turn_context", let payload = value["payload"] as? [String: Any],
              let model = (payload["model"] as? String).flatMap(Self.bounded) else { return nil }
        return AgentModelState(model: model, effort: (payload["effort"] as? String).flatMap(Self.bounded))
    }
    private func antigravity(_ value: [String: Any]) -> AgentModelState? {
        guard value["type"] as? String == "PLANNER_RESPONSE",
              let model = (value["model"] as? String).flatMap(Self.bounded) else { return nil }
        return AgentModelState(model: model)
    }
    private static func bounded(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 160, !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return value
    }
}
