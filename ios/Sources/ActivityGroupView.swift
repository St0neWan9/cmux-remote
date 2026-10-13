import SwiftUI
import CmuxRemoteCore

/// Details stay accessible behind one quiet summary instead of filling the conversation with cards.
struct ActivityGroupView: View {
    let item: ConversationTimelineItem
    var projectRoot: String?
    var openFile: ((String) -> Void)?
    var images: [ConversationImageReference] = []
    var openImage: ((ConversationImageReference) -> Void)?
    var openDetail: ((String, String) -> Void)?
    @State private var expanded = false
    var body: some View {
        if item.operationCount == 0 {
            // Only reasoning, no operations: nothing to summarize, so it is shown directly.
            rows.frame(maxWidth: .infinity, alignment: .leading)
        } else { group }
    }
    /// Consecutive operations sit next to each other; reasoning text is set apart by a small gap.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(item.messages.enumerated()), id: \.element.id) { index, message in
                let row = MessageRow(message: message, projectRoot: projectRoot, openFile: openFile, images: images, openImage: openImage, openDetail: openDetail)
                let previousIsOperation = index > 0 && MessageRow(message: item.messages[index - 1]).isOperation
                row.padding(.top, index == 0 || (row.isOperation && previousIsOperation) ? 0 : 8)
            }
        }
    }
    private var group: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "book.pages")
                    if item.operationCount == 1 { Text(String(localized: "chat.activity_one")) }
                    else { Text(String.localizedStringWithFormat(String(localized: "chat.activity_count"), item.operationCount)) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.medium))
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("activity." + item.id).accessibilityValue(expanded ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if expanded {
                rows
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
