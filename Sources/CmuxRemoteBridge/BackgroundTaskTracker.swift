import Foundation
import CmuxRemoteCore

/// Finds the tasks an agent started in the background and has not finished.
///
/// A background launch returns a task id at once and reports completion later, in a
/// `<task-notification>` block that names the originating tool call. Pairing those two is what makes
/// "still running" knowable: a launch whose id no completion has named is still in flight. The
/// transcript is the only source — the agent exposes no API for it.
///
/// Tasks outlive the turn that started them, so this reads the whole record rather than the newest page.
struct BackgroundTaskTracker {
    /// The tools that always detach: the call itself is the task, with no flag to read.
    ///
    /// `Monitor` watches a condition and `Workflow` runs a script; both return a task id at once, so
    /// their input carries no `run_in_background`. Waiting for that flag here would miss them entirely.
    static let alwaysDetached: Set<String> = ["Monitor", "Workflow"]

    /// The tools that detach only when the agent asks them to. A foreground call of either ends with
    /// its own turn, so the flag is what separates a task from ordinary work. `TaskStop` ends a task
    /// rather than starting one, so it is not here.
    static let optionallyDetached: Set<String> = ["Bash", "Agent"]
    func running(in lines: [String]) -> [BackgroundAgentTask] {
        var launched: [String: BackgroundAgentTask] = [:]
        for line in lines {
            // Every refresh walks the whole record, so a cheap substring test keeps the JSON parse for
            // the few rows that can carry either signal. Nothing else in a record can start or finish a task.
            guard Self.carriesASignal(line) else { continue }
            guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for call in Self.toolCalls(in: value) where Self.runsInBackground(call) {
                guard let id = call["id"] as? String else { continue }
                let input = call["input"] as? [String: Any] ?? [:]
                let summary = (input["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (input["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (call["name"] as? String) ?? ""
                launched[id] = BackgroundAgentTask(id: id, tool: call["name"] as? String ?? "Task", summary: Self.shorten(summary))
            }
            // A completion notice names the tool call it finishes.
            for id in Self.completedToolUseIDs(in: value) { launched[id] = nil }
        }
        return launched.values.sorted { $0.id < $1.id }
    }
    /// Whether a row can carry either signal: a detached call, or a notice that finishes one.
    ///
    /// A tool that always detaches says so by name rather than by a flag, so its name is part of the test.
    private static func carriesASignal(_ line: String) -> Bool {
        if line.contains("task-notification") || line.contains("run_in_background") { return true }
        return alwaysDetached.contains { line.contains("\"" + $0 + "\"") }
    }
    /// Every `tool_use` block on one transcript record.
    private static func toolCalls(in value: [String: Any]) -> [[String: Any]] {
        guard let message = value["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
        return content.filter { $0["type"] as? String == "tool_use" }
    }
    /// Whether one tool call detached.
    private static func runsInBackground(_ call: [String: Any]) -> Bool {
        guard let name = call["name"] as? String else { return false }
        if alwaysDetached.contains(name) { return true }
        guard optionallyDetached.contains(name) else { return false }
        let input = call["input"] as? [String: Any] ?? [:]
        return input["run_in_background"] as? Bool == true || input["runInBackground"] as? Bool == true
    }
    /// The tool-call ids a `<task-notification>` block finishes.
    ///
    /// The block reaches the record in more than one shape: a queue row's own `content`, an
    /// `attachment`'s `prompt`, and a `tool_result`'s content inside a user message. All are searched so
    /// a finished task is never left looking like it is still running.
    private static func completedToolUseIDs(in value: [String: Any]) -> [String] {
        let texts = Self.noticeTexts(in: value)
        let matches = texts.flatMap { $0.contains("<task-notification>") ? Self.matches(#"<tool-use-id>([^<]+)</tool-use-id>"#, in: $0) : [] }
        return matches
    }
    /// Every string on one record that could carry a completion notice.
    private static func noticeTexts(in value: [String: Any]) -> [String] {
        var texts: [String] = []
        func collect(_ any: Any?) {
            switch any {
            case let text as String: texts.append(text)
            case let items as [[String: Any]]: for item in items { collect(item["content"]); collect(item["text"]) }
            case let object as [String: Any]: collect(object["content"]); collect(object["text"]); collect(object["prompt"])
            default: break
            }
        }
        collect(value["content"])
        collect(value["attachment"])
        collect(value["message"])
        return texts
    }
    /// The capture groups of every match of `pattern` in `text`.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }
    /// The first line of a command, bounded, so a long script does not become the label.
    private static func shorten(_ text: String) -> String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
        return first.count <= 120 ? first : String(first.prefix(117)) + "…"
    }
}
