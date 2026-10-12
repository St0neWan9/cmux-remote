import SwiftUI

/// Native selectable Markdown prose with separate code blocks and paragraph rhythm.
struct MarkdownMessageView: View {
    let text: String
    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                if block.code {
                    // Nested code scrolling was blank in the live timeline.
                    // Wrapping keeps the selectable content in the parent layer.
                    Text(block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("markdown.code.\(block.id)")
                } else if let level = block.headingLevel {
                    Text(.init(block.text)).font(level == 1 ? .title2 : level == 2 ? .title3 : .headline).bold()
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                } else if let marker = block.listMarker {
                    HStack(alignment: .top, spacing: 10) {
                        Text(marker)
                        Text(.init(block.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.body).lineSpacing(5)
                } else {
                    Text(.init(block.text)).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
