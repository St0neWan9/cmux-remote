import Foundation

/// Selectable Markdown segments preserve the original code inside each fence.
struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let code: Bool
    static func parse(_ text: String) -> [Self] {
        text.components(separatedBy: "```").enumerated().compactMap { index, value in
            var content = value.trimmingCharacters(in: .newlines)
            if index % 2 == 1, let newline = content.firstIndex(of: "\n") {
                let language = content[..<newline]
                if !language.contains(" ") { content = String(content[content.index(after: newline)...]) }
            }
            return content.isEmpty ? nil : Self(id: index, text: content, code: index % 2 == 1)
        }
    }
}
