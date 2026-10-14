import Foundation
import CmuxRemoteCore

/// Reads the agent's live working line off the terminal.
///
/// Claude and Codex render their progress in the terminal itself, e.g.
/// `✻ Blanching… (54s · ↓ 2.3k tokens)`. Neither the gerund nor the token count reaches the transcript
/// or any provider API, so the only source is the rendered screen, read exactly as a person sees it.
struct TuiAgentStatusLine {
    /// Glyphs the agents cycle through for the working spinner.
    static let glyphs: Set<Character> = ["✢", "✶", "✻", "✽", "✳", "∗", "⟢", "✦", "✧", "◐", "◓", "◑", "◒"]
    /// The glyph also begins the mode bar and ordinary prose, so only a row with an ellipsis or a
    /// timer after it can be the working line.
    static func parse(rows: [String]) -> TuiAgentStatus? {
        for row in rows.reversed() {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard let glyph = trimmed.first, glyphs.contains(glyph) else { continue }
            let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { continue }
            let activity = gerund(rest)
            let elapsed = elapsedSeconds(rest)
            guard activity != nil || elapsed != nil else { continue }
            // A settled turn leaves `✻ Brewed for 30s` behind: a bare timer with no throughput and no
            // parenthesis. A live line always carries one of the two, or has not named its work yet.
            if activity == nil, elapsed != nil, tokenDirection(rest) == nil, !rest.contains("(") { continue }
            // Compaction prints its own word on the working line, which the phone shows in place of the
            // activity the agent would otherwise name.
            let compacting = rest.lowercased().contains("compact")
            return TuiAgentStatus(glyph: String(glyph), activity: compacting ? nil : activity, elapsedSeconds: elapsed,
                                  tokenCount: tokenCount(rest), tokensAscending: tokenDirection(rest), isCompacting: compacting)
        }
        return nil
    }
    /// The activity word and its ellipsis (`Blanching…`), which the agent prints before any timer.
    private static func gerund(_ text: String) -> String? {
        guard let end = text.firstIndex(of: "…") else { return nil }
        let value = String(text[text.startIndex...end]).trimmingCharacters(in: .whitespaces)
        // The activity is one word plus the ellipsis; a sentence ending in an ellipsis is not a gerund.
        return value.isEmpty || value.count > 40 || value.contains("  ") ? nil : value
    }
    /// The elapsed seconds, from either `(54s` / `(1m05s)` or the bare `· 3s ·` form the agent uses
    /// while it runs stop hooks.
    private static func elapsedSeconds(_ text: String) -> Int? {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard chars[index].isNumber, index == 0 || !(chars[index - 1].isLetter || chars[index - 1].isNumber) else { index += 1; continue }
            var cursor = index, minutes = 0
            var digits = ""
            while cursor < chars.count, chars[cursor].isNumber { digits.append(chars[cursor]); cursor += 1 }
            if cursor < chars.count, chars[cursor] == "m" {
                let afterM = cursor + 1
                if afterM < chars.count, chars[afterM].isNumber {
                    minutes = Int(digits) ?? 0
                    cursor = afterM; digits = ""
                    while cursor < chars.count, chars[cursor].isNumber { digits.append(chars[cursor]); cursor += 1 }
                }
            }
            if cursor < chars.count, chars[cursor] == "s" {
                let afterS = cursor + 1
                if afterS >= chars.count || !chars[afterS].isLetter, let seconds = Int(digits) {
                    return minutes * 60 + seconds
                }
            }
            index = cursor
        }
        return nil
    }
    /// The token count as printed (`2.3k`, `560`), without its arrow.
    private static func tokenCount(_ text: String) -> String? {
        let chars = Array(text)
        for (index, char) in chars.enumerated() where char == "↓" || char == "↑" {
            var cursor = index + 1
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            var value = ""
            while cursor < chars.count, chars[cursor].isNumber || chars[cursor] == "." { value.append(chars[cursor]); cursor += 1 }
            if cursor < chars.count, chars[cursor] == "k" { value.append("k"); cursor += 1 }
            if !value.isEmpty { return value }
        }
        return nil
    }
    private static func tokenDirection(_ text: String) -> Bool? {
        if text.contains("↑") { return true }
        if text.contains("↓") { return false }
        return nil
    }
}
