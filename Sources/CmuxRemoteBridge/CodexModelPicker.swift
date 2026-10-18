import Foundation

/// Reads the Codex `/model` picker from rendered rows: which list is open, its numbered entries and the highlight.
///
/// The picker first lists models (`Select Model and Effort`), then the chosen model's reasoning levels
/// (`Select Reasoning Level for …`). Entries are `N. Label  description`, the highlighted one marked with `›`.
struct CodexModelPicker {
    enum Stage: Equatable { case model, effort }
    struct Entry: Equatable { let number: Int; let label: String }
    struct Screen: Equatable {
        let stage: Stage
        let title: String
        let entries: [Entry]
        let highlighted: Int?
    }
    func screen(_ rows: [String]) -> Screen? {
        guard let titleIndex = rows.lastIndex(where: { $0.contains("Select Reasoning Level") || $0.contains("Select Model") }) else { return nil }
        let title = rows[titleIndex].trimmingCharacters(in: .whitespaces)
        var entries: [Entry] = [], highlighted: Int?
        for row in rows[(titleIndex + 1)...] {
            var body = Substring(row).drop(while: { $0 == " " })
            let marked = body.hasPrefix("›")
            if marked { body = body.dropFirst().drop(while: { $0 == " " }) }
            let digits = body.prefix(while: \.isNumber)
            guard (1...2).contains(digits.count), let number = Int(digits), body.dropFirst(digits.count).hasPrefix(". ") else { continue }
            let text = body.dropFirst(digits.count + 2).trimmingCharacters(in: .whitespaces)
            // The label is the first column; the description follows after a run of spaces.
            var label = text.components(separatedBy: "  ").first ?? text
            for suffix in [" (current)", " (default)"] where label.hasSuffix(suffix) { label = String(label.dropLast(suffix.count)) }
            entries.append(Entry(number: number, label: label.trimmingCharacters(in: .whitespaces)))
            if marked { highlighted = number }
        }
        guard !entries.isEmpty else { return nil }
        return Screen(stage: title.contains("Reasoning Level") ? .effort : .model, title: title, entries: entries, highlighted: highlighted)
    }
    /// The model entry naming one of the candidates, compared as Codex writes slugs: lowercased, spaces as hyphens.
    func number(matching candidates: [String], in screen: Screen) -> Int? {
        let wanted = Set(candidates.map(Self.normalized))
        return screen.entries.first { wanted.contains(Self.normalized($0.label)) }?.number
    }
    /// The reasoning level a transcript recorded, as the picker labels it; nil leaves the picker's own default.
    func number(effort: String?, in screen: Screen) -> Int? {
        guard let effort = effort?.lowercased() else { return nil }
        return screen.entries.first { entry in
            let label = entry.label.lowercased()
            return (label == "extra high" ? "xhigh" : label) == effort
        }?.number
    }
    static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }
}
