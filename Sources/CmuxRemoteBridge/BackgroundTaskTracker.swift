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
///
/// Some endings leave no notice: a Monitor that reaches its own timeout, and a task stopped with
/// `TaskStop`. The first is bounded by the deadline its input declares; the second is matched through the
/// task id the launch result reports, which is the id `TaskStop` names.
struct BackgroundTaskTracker {
    /// One detached call, and the moment it can no longer be running when it declares one.
    struct Launch: Sendable, Equatable {
        let task: BackgroundAgentTask
        let deadline: Date?
        func isRunning(at now: Date) -> Bool { deadline.map { now < $0 } ?? true }
    }
    /// A Monitor without `timeout_ms` uses the tool's default, and none outlives the tool's ceiling.
    static let monitorDefaultTimeout: TimeInterval = 300
    static let monitorMaximumTimeout: TimeInterval = 3_600
    /// The tools that always detach: the call itself is the task, with no flag to read.
    ///
    /// `Monitor` watches a condition and `Workflow` runs a script; both return a task id at once, so
    /// their input carries no `run_in_background`. Waiting for that flag here would miss them entirely.
    static let alwaysDetached: Set<String> = ["Monitor", "Workflow"]

    /// The tools that detach only when the agent asks them to. A foreground call of either ends with
    /// its own turn, so the flag is what separates a task from ordinary work. `TaskStop` ends a task
    /// rather than starting one, so it is not here.
    static let optionallyDetached: Set<String> = ["Bash", "Agent"]
    func running(in lines: [String], at now: Date) -> [BackgroundAgentTask] {
        launches(in: lines).filter { $0.isRunning(at: now) }.map(\.task)
    }
    /// Every detached call no completion, stop or notice has ended, with the deadline it declares.
    func launches(in lines: [String]) -> [Launch] {
        var launched: [String: Launch] = [:]
        /// The task id each launch reported, which is how `TaskStop` names it.
        var toolUseByTaskID: [String: String] = [:]
        for line in lines {
            // Every refresh walks the whole record, so a cheap substring test keeps the JSON parse for
            // the few rows that can carry a signal. Nothing else in a record can start or finish a task.
            guard Self.carriesASignal(line) else { continue }
            guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let stamp = Self.timestamp(value["timestamp"] as? String)
            for call in Self.toolCalls(in: value) {
                guard let id = call["id"] as? String else { continue }
                let input = call["input"] as? [String: Any] ?? [:]
                if call["name"] as? String == "TaskStop" {
                    for taskID in [input["task_id"], input["shell_id"]].compactMap({ $0 as? String }) {
                        if let launch = toolUseByTaskID[taskID] { launched[launch] = nil }
                    }
                    continue
                }
                guard Self.runsInBackground(call) else { continue }
                let summary = (input["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (input["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (call["name"] as? String) ?? ""
                launched[id] = Launch(task: BackgroundAgentTask(id: id, tool: call["name"] as? String ?? "Task", summary: Self.shorten(summary)),
                                      deadline: call["name"] as? String == "Monitor" ? Self.monitorDeadline(input, launchedAt: stamp) : nil)
            }
            for (toolUseID, text) in Self.toolResults(in: value) where launched[toolUseID] != nil {
                if let taskID = Self.matches(#"(?:with ID: |Monitor started \(task |agentId: )([A-Za-z0-9_-]+)"#, in: text).first {
                    toolUseByTaskID[taskID] = toolUseID
                }
            }
            // A completion notice names the tool call it finishes.
            for id in Self.completedToolUseIDs(in: value) { launched[id] = nil }
        }
        return launched.values.sorted { $0.task.id < $1.task.id }
    }
    /// When a Monitor stops on its own: launch time plus its declared timeout, never past the ceiling.
    private static func monitorDeadline(_ input: [String: Any], launchedAt: Date?) -> Date? {
        guard let launchedAt else { return nil }
        let declared = (input["timeout_ms"] as? NSNumber).map { $0.doubleValue / 1000 } ?? monitorDefaultTimeout
        return launchedAt.addingTimeInterval(min(max(declared, 0), monitorMaximumTimeout))
    }
    private static func timestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(text, strategy: .iso8601))
    }
    /// Each `tool_result` block on one record, with its text.
    private static func toolResults(in value: [String: Any]) -> [(String, String)] {
        guard let message = value["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { block in
            guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
            if let text = block["content"] as? String { return (id, text) }
            let parts = (block["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
            return (id, parts.joined(separator: "\n"))
        }
    }
    /// Whether a row can carry either signal: a detached call, or a notice that finishes one.
    ///
    /// A tool that always detaches says so by name rather than by a flag, so its name is part of the test.
    private static func carriesASignal(_ line: String) -> Bool {
        if line.contains("task-notification") || line.contains("run_in_background") || line.contains("\"TaskStop\"") { return true }
        // A launch result reports the task id that a later `TaskStop` names.
        if line.contains("running in background with ID") || line.contains("Monitor started (task") || line.contains("agentId:") { return true }
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
