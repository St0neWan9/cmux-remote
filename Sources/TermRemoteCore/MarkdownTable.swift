import Foundation

/// A GitHub-style pipe table: a header row, a delimiter row, then body rows.
public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable { case leading, center, trailing }
    public let header: [String]
    public let alignments: [Alignment]
    /// Body rows padded or trimmed to the header's column count.
    public let rows: [[String]]

    /// Reads a table from consecutive lines, or nil when the first two lines are not a header and delimiter.
    public init?(lines: [String]) {
        guard lines.count >= 2, let header = Self.cells(lines[0]), let delimiter = Self.cells(lines[1]),
              header.count == delimiter.count, !header.isEmpty else { return nil }
        var alignments: [Alignment] = []
        for cell in delimiter {
            let rule = cell.trimmingCharacters(in: .whitespaces)
            guard rule.count >= 1, rule.allSatisfy({ $0 == "-" || $0 == ":" }), rule.contains("-") else { return nil }
            let left = rule.hasPrefix(":"), right = rule.hasSuffix(":")
            alignments.append(left && right ? .center : right ? .trailing : .leading)
        }
        self.header = header; self.alignments = alignments
        rows = lines.dropFirst(2).compactMap { line in
            guard let cells = Self.cells(line) else { return nil }
            return Array((cells + Array(repeating: "", count: max(0, header.count - cells.count))).prefix(header.count))
        }
    }

    /// Whether a line can belong to a table: it has an unescaped pipe outside inline code.
    public static func isRow(_ line: String) -> Bool { cells(line) != nil }

    /// Splits a row on unescaped pipes outside inline code, dropping the optional outer pipes.
    static func cells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells: [String] = [], current = "", inCode = false, escaped = false
        for character in trimmed {
            if escaped { current.append(character); escaped = false; continue }
            switch character {
            case "\\": escaped = true; current.append(character)
            case "`": inCode.toggle(); current.append(character)
            case "|" where !inCode: cells.append(current); current = ""
            default: current.append(character)
            }
        }
        cells.append(current)
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|"), cells.count > 0 { cells.removeLast() }
        guard !cells.isEmpty else { return nil }
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
    }
}
