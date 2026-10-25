import Foundation
import CmuxRemoteCore

/// Selectable Markdown segments preserve the original code inside each fence.
struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let code: Bool
    var headingLevel: Int? = nil
    var listMarker: String? = nil
    var table: MarkdownTable? = nil
    /// Inline styles parsed once. `Text(.init(_:))` re-parses Markdown every time SwiftUI lays the row out,
    /// which on a streaming conversation with long messages kept the main thread busy.
    let attributed: AttributedString
    init(id: Int, text: String, code: Bool, headingLevel: Int? = nil, listMarker: String? = nil, table: MarkdownTable? = nil) {
        self.id = id; self.text = text; self.code = code
        self.headingLevel = headingLevel; self.listMarker = listMarker; self.table = table
        attributed = code ? AttributedString(text)
            : (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)))
              ?? AttributedString(text)
    }
    static func parse(_ text: String) -> [Self] {
        var blocks: [Self] = []
        for (index, value) in text.components(separatedBy: "```").enumerated() {
            var content = value
            if index % 2 == 1, let newline = content.firstIndex(of: "\n") {
                // The line directly after the opening fence is the optional language.
                // Preserve the leading newline until it is removed, so bare fences
                // cannot mistake the first code line for a language label.
                content = String(content[content.index(after: newline)...])
            }
            content = content.trimmingCharacters(in: .newlines)
            guard !content.isEmpty else { continue }
            if index % 2 == 1 { blocks.append(Self(id: blocks.count, text: content, code: true)); continue }
            var paragraph: [String] = []
            let lines = content.components(separatedBy: "\n")
            var position = 0
            while position < lines.count {
                let line = lines[position]
                // A pipe table runs from its header and delimiter rows to the last consecutive pipe row.
                if MarkdownTable.isRow(line), position + 1 < lines.count, MarkdownTable(lines: [line, lines[position + 1]]) != nil {
                    var end = position + 2
                    while end < lines.count, MarkdownTable.isRow(lines[end]) { end += 1 }
                    if let table = MarkdownTable(lines: Array(lines[position..<end])) {
                        if !paragraph.isEmpty {
                            blocks.append(Self(id: blocks.count, text: paragraph.joined(separator: "\n"), code: false))
                            paragraph = []
                        }
                        blocks.append(Self(id: blocks.count, text: lines[position..<end].joined(separator: "\n"), code: false, table: table))
                        position = end
                        continue
                    }
                }
                position += 1
                let structural = structure(line)
                if line.isEmpty || structural != nil {
                    if !paragraph.isEmpty {
                        blocks.append(Self(id: blocks.count, text: paragraph.joined(separator: "\n"), code: false))
                        paragraph = []
                    }
                    if let structural {
                        blocks.append(Self(id: blocks.count, text: structural.text, code: false,
                            headingLevel: structural.headingLevel, listMarker: structural.listMarker))
                    }
                } else { paragraph.append(line) }
            }
            if !paragraph.isEmpty { blocks.append(Self(id: blocks.count, text: paragraph.joined(separator: "\n"), code: false)) }
        }
        return blocks
    }
    private static func structure(_ line: String) -> Self? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard line.prefix(while: { $0 == " " }).count <= 3 else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
            return Self(id: 0, text: String(trimmed.dropFirst(hashes + 1)), code: false, headingLevel: hashes)
        }
        if ["- ", "* ", "+ "].contains(where: trimmed.hasPrefix) {
            return Self(id: 0, text: String(trimmed.dropFirst(2)), code: false, listMarker: "•")
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") {
            return Self(id: 0, text: String(trimmed.dropFirst(digits.count + 2)), code: false, listMarker: String(digits) + ".")
        }
        return nil
    }
}
