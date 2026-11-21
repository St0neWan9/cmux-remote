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
        guard let index = promptRowIndex(in: rows, typedRows: typedRows, provider: provider) else { return false }
        let tail = rows[(index + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if hasBlockingHint(in: tail, provider: provider) { return false }
        guard remainderAfterPrompt(typedRows[index], provider: provider).trimmingCharacters(in: .whitespaces).isEmpty else { return false }
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
        guard let index = promptRowIndex(in: rows, typedRows: typedRows, provider: provider) else { return nil }
        let tail = rows[(index + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if hasBlockingHint(in: tail, provider: provider) { return nil }
        var lines = [remainderAfterPrompt(typedRows[index], provider: provider)]
        for row in (index + 1)..<rows.count {
            let value = rows[row].trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.unicodeScalars.allSatisfy({ (0x2500...0x257f).contains($0.value) || $0 == " " }) { break }
            lines.append(String(body(typedRows[row])))
        }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Whether `rows` shows Antigravity's own framed composer (`────` divider adjacent to `>`).
    static func hasAntigravityPrompt(in rows: [String]) -> Bool {
        for index in stride(from: rows.count - 1, through: 0, by: -1) {
            let content = rows[index].trimmingCharacters(in: .whitespaces)
            guard content == ">" || content.hasPrefix("> ") || content.hasPrefix(">\u{00a0}") else { continue }
            if isAntigravityFramed(rows: rows, index: index) { return true }
        }
        return false
    }
    private func promptRowIndex(in rows: [String], typedRows: [String], provider: String) -> Int? {
        if provider == "antigravity" {
            for index in stride(from: rows.count - 1, through: 0, by: -1) {
                let row = body(rows[index])
                let typed = body(typedRows[index])
                guard Self.matchesAntigravityPrefix(row), Self.matchesAntigravityPrefix(typed),
                      Self.isAntigravityFramed(rows: rows, index: index) else { continue }
                return index
            }
            return nil
        }
        let prefix = provider == "claude" ? "❯\u{00a0}" : "› "
        guard let index = rows.lastIndex(where: { body($0).hasPrefix(prefix) }), body(typedRows[index]).hasPrefix(prefix) else { return nil }
        return index
    }
    private func remainderAfterPrompt(_ line: String, provider: String) -> String {
        let content = body(line)
        if provider == "antigravity" {
            guard content.hasPrefix(">") else { return String(content) }
            let dropped = content.dropFirst()
            if dropped.first == " " || dropped.first == "\u{00a0}" { return String(dropped.dropFirst()) }
            return String(dropped)
        }
        let prefix = provider == "claude" ? "❯\u{00a0}" : "› "
        return String(content.dropFirst(prefix.count))
    }
    private func hasBlockingHint(in tail: [String], provider: String) -> Bool {
        let dialogHints = ["esc to go back", "press enter to", "enter to confirm", "enter to select"]
        return tail.suffix(6).contains { row in
            let lower = row.lowercased()
            if dialogHints.contains(where: { lower.contains($0) }) { return true }
            if lower.contains("esc to cancel") {
                // Antigravity's persistent mode bar shows `esc to cancel ... auto · Gemini ...` while running.
                if provider == "antigravity", row.contains(" · ") { return false }
                return true
            }
            return false
        }
    }
    private static func matchesAntigravityPrefix(_ text: Substring) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == ">" || text.hasPrefix("> ") || text.hasPrefix(">\u{00a0}")
    }
    private static func isAntigravityFramed(rows: [String], index: Int) -> Bool {
        let above = index > 0 && isDivider(rows[index - 1])
        let below = (index + 1..<min(rows.count, index + 6)).contains { isDivider(rows[$0]) }
        return above || below
    }
    private static func isDivider(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8 else { return false }
        return trimmed.unicodeScalars.allSatisfy { (0x2500...0x257f).contains($0.value) }
    }
    private func body(_ line: String) -> Substring {
        var value = line.drop(while: { $0 == " " })
        if value.hasPrefix("│") { value = value.dropFirst().drop(while: { $0 == " " }) }
        return value
    }
}
