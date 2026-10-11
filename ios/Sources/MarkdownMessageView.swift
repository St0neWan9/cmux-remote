import SwiftUI

/// Native selectable Markdown prose with separate code blocks and paragraph rhythm.
struct MarkdownMessageView: View {
    let text: String
    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }
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
