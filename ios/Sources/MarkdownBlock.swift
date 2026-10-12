import Foundation

/// Selectable Markdown segments preserve the original code inside each fence.
struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let code: Bool
    var headingLevel: Int? = nil
    var listMarker: String? = nil
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
            for line in content.components(separatedBy: "\n") {
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
