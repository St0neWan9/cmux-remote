import Foundation

/// Extracts Antigravity CLI's in-progress streaming prose from rendered terminal screen rows.
///
/// Antigravity renders a Braille spinner status line (`⠋ Thinking...`, `⣷ Running command...`) directly
/// above its composer divider (`────`) and shows `esc to cancel` on its bottom mode bar while a turn runs.
/// Committed blocks above the live answer begin with `●`, `○`, `… `, or a `> ` prompt echo.
/// Conservative and best-effort: returns `nil` whenever no actively streaming prose is clearly present.
public struct AntigravityProseScreenExtractor: Sendable {
    private static let maxAnswerLines = 200

    public init() {}

    public func extract(lines: [String]) -> String? {
        let rows = lines.map(Self.trimTrailing)
        guard let anchor = Self.statusLineIndex(in: rows), anchor > 0 else { return nil }

        let lowerBound = max(0, anchor - Self.maxAnswerLines)
        var collected: [String] = []
        var index = anchor - 1
        while index >= lowerBound {
            let row = rows[index]
            // Committed blocks (`●`, `○`, `> `, `… N more actions …`) must always stop the walk
            // before chrome skipping, so a `● Running (...) (ctrl+o to expand)` row is never stepped over.
            if Self.isBoundary(row) { break }
            if Self.isScreenChrome(row) { index -= 1; continue }
            collected.append(row)
            index -= 1
        }
        collected.reverse()
        let cleaned = Self.collapsingBlankRuns(collected)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func statusLineIndex(in rows: [String]) -> Int? {
        // Rex snapshots include full scrollback, so the active status line and mode bar
        // are only valid near the bottom of the screen (never inside old scrollback prose
        // that happens to mention "esc to cancel" or a Braille character).
        let nonEmpty = rows.indices.filter { !rows[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        guard let lastNonEmpty = nonEmpty.last else { return nil }
        let footerWindow = Set(nonEmpty.suffix(4))
        let spinnerWindow = Set(nonEmpty.suffix(12))

        // Tier 1: Braille spinner status line directly above the composer box (`⣷  Running command...`).
        for index in stride(from: lastNonEmpty, through: 0, by: -1) where spinnerWindow.contains(index) {
            if isBrailleStatusLine(rows[index]) { return index }
        }
        // Tier 2: Active turn mode bar at the very bottom (`esc to cancel ... auto · Gemini ...`),
        // stepping above the composer box.
        for index in stride(from: lastNonEmpty, through: 0, by: -1) where footerWindow.contains(index) {
            let trimmed = rows[index].trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("esc to cancel") {
                var cursor = index - 1
                while cursor >= 0 {
                    let line = rows[cursor].trimmingCharacters(in: .whitespaces)
                    if line.isEmpty || isScreenChrome(rows[cursor]) || line == ">" || line.hasPrefix("> ") {
                        cursor -= 1
                    } else {
                        break
                    }
                }
                return cursor + 1
            }
        }
        return nil
    }

    static func isBrailleStatusLine(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.unicodeScalars.first,
              (0x2800...0x28FF).contains(first.value) else { return false }
        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        return !rest.isEmpty
    }

    static func isScreenChrome(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return false }
        if boxDrawingGlyphs.contains(first) { return true }
        if trimmed.hasPrefix("└ Tip:") || trimmed.hasPrefix("Tip:") { return true }
        let lower = trimmed.lowercased()
        if lower.contains("esc to cancel") { return true }
        if AntigravityQueuedScreenExtractor.isQueuedEditHint(trimmed) { return true }
        if trimmed == ">" { return true }
        return false
    }

    static func isBoundary(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return false }
        if boundaryGlyphs.contains(first) { return true }
        if trimmed.hasPrefix("… ") && trimmed.hasSuffix("…") { return true }
        if trimmed.hasPrefix("⎿") { return true }
        return false
    }

    private static let boxDrawingGlyphs: Set<Character> = [
        "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘", "─", "━", "═", "├", "┤", "┬", "┴", "┼", "│", "┃",
    ]

    private static let boundaryGlyphs: Set<Character> = ["●", "○", "❯", ">", "⏺"]

    private static func trimTrailing(_ row: String) -> String {
        var scalars = Array(row.unicodeScalars)
        while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func collapsingBlankRuns(_ rows: [String]) -> [String] {
        var out: [String] = []
        var previousBlank = false
        for row in rows {
            let isBlank = row.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if previousBlank { continue }
                previousBlank = true
            } else {
                previousBlank = false
            }
            out.append(row)
        }
        while out.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeFirst() }
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
        return out
    }
}
