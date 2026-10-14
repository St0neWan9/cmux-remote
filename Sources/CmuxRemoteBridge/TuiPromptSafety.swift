import Foundation

/// Conservative plain-screen adaptation of CMUXAgentLaunch/AgentPromptInputState.
/// Faint placeholders require decoded daemon replay style proof; unknown screens block typing.
public struct TuiPromptSafety: Sendable {
    public init() {}
    public func isEmpty(_ screen: String, provider: String) -> Bool {
        let rows = screen.components(separatedBy: .newlines)
        return isEmpty(rows: rows, typedRows: rows, provider: provider)
    }
    func isEmpty(_ state: TuiTerminalState, provider: String) -> Bool {
        isEmpty(rows: state.rows, typedRows: state.typedRows, provider: provider)
    }
    private func isEmpty(rows: [String], typedRows: [String], provider: String) -> Bool {
        let prefix = provider == "claude" ? "❯\u{00a0}" : "› "
        guard let index = rows.lastIndex(where: { body($0).hasPrefix(prefix) }), body(typedRows[index]).hasPrefix(prefix) else { return false }
        let hints = ["esc to cancel", "esc to go back", "press enter to", "enter to confirm", "enter to select"]
        let tail = rows[(index + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if tail.suffix(6).contains(where: { row in hints.contains { row.lowercased().contains($0) } }) { return false }
        guard body(typedRows[index]).dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        for row in (index + 1)..<rows.count {
            let value = rows[row].trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.unicodeScalars.allSatisfy({ (0x2500...0x257f).contains($0.value) || $0 == " " }) { break }
            if !typedRows[row].trimmingCharacters(in: .whitespaces).isEmpty { return false }
        }
        return true
    }
    /// The typed (non-faint) text of an open prompt, joined across wrapped rows; nil when no plain prompt is shown.
    func typedText(_ state: TuiTerminalState, provider: String) -> String? {
        let rows = state.rows, typedRows = state.typedRows
        let prefix = provider == "claude" ? "❯\u{00a0}" : "› "
        guard let index = rows.lastIndex(where: { body($0).hasPrefix(prefix) }), body(typedRows[index]).hasPrefix(prefix) else { return nil }
        let hints = ["esc to cancel", "esc to go back", "press enter to", "enter to confirm", "enter to select"]
        let tail = rows[(index + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if tail.suffix(6).contains(where: { row in hints.contains { row.lowercased().contains($0) } }) { return nil }
        var lines = [String(body(typedRows[index]).dropFirst(prefix.count))]
        for row in (index + 1)..<rows.count {
            let value = rows[row].trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.unicodeScalars.allSatisfy({ (0x2500...0x257f).contains($0.value) || $0 == " " }) { break }
            lines.append(String(body(typedRows[row])))
        }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func body(_ line: String) -> Substring {
        var value = line.drop(while: { $0 == " " })
        if value.hasPrefix("│") { value = value.dropFirst().drop(while: { $0 == " " }) }
        return value
    }
}
