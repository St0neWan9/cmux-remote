import Foundation

/// Whether the agent is compacting its context, read from the terminal it renders into.
///
/// Compaction is the one moment a working turn shows no visible progress, and it is not in the
/// transcript: the agent prints it on its own working line, so the rendered screen is the only source.
struct TuiCompactionScreen {
    /// The glyphs the agents cycle through for the working spinner. A prose row never begins with one,
    /// so a glyph-led row is agent chrome rather than something the agent wrote.
    private static let glyphs: Set<Character> = ["✢", "✶", "✻", "✽", "✳", "∗", "⟢", "✦", "✧", "◐", "◓", "◑", "◒"]
    static func isCompacting(rows: [String]) -> Bool {
        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, glyphs.contains(first) else { continue }
            if trimmed.lowercased().contains("compact") { return true }
        }
        return false
    }
}
