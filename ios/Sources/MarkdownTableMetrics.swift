import UIKit
import CmuxRemoteCore

/// Column widths for a Markdown table that fits its message: columns wrap down to their longest
/// unbreakable piece before the table is allowed to grow wider than the space it is given.
struct MarkdownTableMetrics {
    /// Each column's width on one line, and the width of its longest piece that cannot wrap.
    let natural: [CGFloat]
    let minimum: [CGFloat]

    init(table: MarkdownTable, body: UIFont, header: UIFont) {
        var natural = Array(repeating: CGFloat(0), count: table.header.count)
        var minimum = natural
        for (index, row) in ([table.header] + table.rows).enumerated() {
            for (column, cell) in row.enumerated() where column < natural.count {
                let runs = Self.runs(cell, font: index == 0 ? header : body)
                natural[column] = max(natural[column], runs.reduce(0) { $0 + Self.width($1.text, $1.font) })
                minimum[column] = max(minimum[column], runs.flatMap { run in Self.pieces(run.text).map { Self.width($0, run.font) } }.max() ?? 0)
            }
        }
        // Rounding up keeps a measured line from wrapping its last word.
        self.natural = natural.map { ceil($0) + 2 }
        self.minimum = zip(minimum, self.natural).map { min(ceil($0) + 2, $1) }
    }

    /// Widths that fill `available`, wrapping only the widest columns; the sum exceeds
    /// `available` only when even the unbreakable pieces do not fit, and then the table scrolls.
    func widths(available: CGFloat, gap: CGFloat) -> [CGFloat] {
        let space = available - gap * CGFloat(max(0, natural.count - 1))
        let wide = natural.reduce(0, +), narrow = minimum.reduce(0, +)
        guard space > 0, !natural.isEmpty else { return minimum }
        if wide <= space {
            // Short tables still span the message; extra room follows each column's content.
            return natural.map { $0 + (space - wide) * $0 / max(wide, 1) }
        }
        guard narrow < space else { return minimum }
        // Short columns keep one line; the widest ones share a common cap that makes the table fit.
        var low: CGFloat = 0, high = natural.max() ?? 0
        for _ in 0..<40 {
            let cap = (low + high) / 2
            if capped(cap).reduce(0, +) > space { high = cap } else { low = cap }
        }
        return capped(low)
    }

    private func capped(_ cap: CGFloat) -> [CGFloat] {
        zip(natural, minimum).map { full, least in min(full, max(least, cap)) }
    }

    private struct Run { let text: String; let font: UIFont }

    /// The cell's inline Markdown as text runs in the fonts the view draws them with.
    private static func runs(_ markdown: String, font: UIFont) -> [Run] {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return [Run(text: markdown, font: font)]
        }
        return parsed.runs.map { run in
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            let styled = intent.contains(.code)
                ? UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: traits.contains(.traitBold) ? .semibold : .regular)
                : font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
            return Run(text: text, font: styled)
        }
    }

    /// Pieces a line cannot break inside: words split at spaces and after hyphens, and single CJK characters.
    /// Text never breaks after an underscore or a slash, so identifiers and paths stay whole.
    private static func pieces(_ text: String) -> [String] {
        var pieces: [String] = [], current = ""
        for character in text {
            if character.isWhitespace { pieces.append(current); current = ""; continue }
            if character.unicodeScalars.contains(where: isIdeographic) { pieces.append(current); pieces.append(String(character)); current = ""; continue }
            current.append(character)
            if character == "-" { pieces.append(current); current = "" }
        }
        pieces.append(current)
        return pieces.filter { !$0.isEmpty }
    }

    private static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
        default: return false
        }
    }

    private static func width(_ text: String, _ font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
