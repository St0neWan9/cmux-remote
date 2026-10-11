import SwiftUI

/// Native selectable Markdown prose with separate code blocks and paragraph rhythm.
struct MarkdownMessageView: View {
    let text: String
    private struct Block: Identifiable {
        let id: Int
        let text: String
        let code: Bool
    }
    private var blocks: [Block] {
        let sections = text.components(separatedBy: "```")
        return sections.enumerated().compactMap { index, value in
            var content = value.trimmingCharacters(in: .newlines)
            if index % 2 == 1, let newline = content.firstIndex(of: "\n") {
                let language = content[..<newline]
                if !language.contains(" ") { content = String(content[content.index(after: newline)...]) }
            }
            return content.isEmpty ? nil : Block(id: index, text: content, code: index % 2 == 1)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                if block.code {
                    ScrollView(.horizontal) {
                        Text(block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(14)
                    }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Text(.init(block.text)).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
