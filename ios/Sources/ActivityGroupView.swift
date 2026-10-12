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
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: item.operationCount == 0 ? "sparkles" : "book.pages")
                    if item.operationCount == 0 { Text(String(localized: "chat.thought")) }
                    else if item.operationCount == 1 { Text(String(localized: "chat.activity_one")) }
                    else { Text(String.localizedStringWithFormat(String(localized: "chat.activity_count"), item.operationCount)) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.medium))
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("activity." + item.id).accessibilityValue(expanded ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if expanded {
                VStack(alignment: .leading, spacing: 14) { ForEach(item.messages) { message in MessageRow(message: message, projectRoot: projectRoot, openFile: openFile, images: images, openImage: openImage, openDetail: openDetail) } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 4)
    }
}
