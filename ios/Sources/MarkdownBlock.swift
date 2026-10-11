import Foundation

/// Selectable Markdown segments preserve the original code inside each fence.
struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let code: Bool
    static func parse(_ text: String) -> [Self] {
        text.components(separatedBy: "```").enumerated().compactMap { index, value in
            var content = value
            if index % 2 == 1, let newline = content.firstIndex(of: "\n") {
                // The line directly after the opening fence is the optional language.
                // Preserve the leading newline until it is removed, so bare fences
                // cannot mistake the first code line for a language label.
                content = String(content[content.index(after: newline)...])
            }
            content = content.trimmingCharacters(in: .newlines)
            return content.isEmpty ? nil : Self(id: index, text: content, code: index % 2 == 1)
        }
    }
}
