import SwiftUI

/// Native Markdown prose with separate code blocks and paragraph rhythm.
///
/// A reply given a `selectionID` is selected in place: a long press turns it into a text view with handles and a menu
/// to add the selection to the chat, copy, share or select the whole turn. Other text uses the system selection.
struct MarkdownMessageView: View {
    let text: String
    var selectionID: String? = nil
    @Environment(\.messageSelection) private var selection
    @Environment(\.selectMessage) private var selectMessage
    @Environment(\.quoteText) private var quoteText
    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }
    var body: some View {
        if let selectionID, let selectMessage {
            if let selection, selection.messageID == selectionID {
                SelectableMessageTextView(text: text, start: selection.point, quote: quoteText) { selectMessage(nil) }
            } else {
                prose(selectable: false)
                    .contentShape(Rectangle())
                    // Released after a long press: the word under the finger is selected where it was pressed.
                    .gesture(LongPressGesture(minimumDuration: 0.4).sequenced(before: DragGesture(minimumDistance: 0)).onEnded { value in
                        guard case .second(true, let drag?) = value else { return }
                        selectMessage(MessageSelection(messageID: selectionID, point: drag.startLocation))
                    })
            }
        } else {
            prose(selectable: true)
        }
    }
    @ViewBuilder private func prose(selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                if block.code {
                    // Nested code scrolling was blank in the live timeline.
                    // Wrapping keeps the selectable content in the parent layer.
                    Text(block.text).font(.system(.callout, design: .monospaced)).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("markdown.code.\(block.id)")
                } else if let table = block.table {
                    MarkdownTableView(table: table).accessibilityIdentifier("markdown.table.\(block.id)")
                } else if let level = block.headingLevel {
                    Text(.init(block.text)).font(level == 1 ? .title2 : level == 2 ? .title3 : .headline).bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                } else if let marker = block.listMarker {
                    HStack(alignment: .top, spacing: 10) {
                        Text(marker)
                        Text(.init(block.text)).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.body).lineSpacing(5)
                } else {
                    Text(.init(block.text)).font(.body).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.modifier(SystemTextSelection(enabled: selectable))
    }
}

/// The system's own selection, for text that is not selected in place.
private struct SystemTextSelection: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}
