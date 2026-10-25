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
    /// Whether this group is the newest item in the conversation. The newest group opens on its own so its
    /// work can be followed as it happens, and closes once the next message arrives.
    var isLatest = false
    /// The reader's own choice, which wins until the group stops being the newest.
    @State private var expanded: Bool?
    /// Groups past this many operations open on their own page: expanding one inside the timeline makes a single
    /// enormous row, which SwiftUI lays out in full and a phone takes seconds to draw.
    static let inlineLimit = 6
    @State private var showingAll = false
    /// The row this group belongs to, so expanding it keeps its place in the timeline.
    @Environment(\.holdPlace) private var holdPlace
    private var isExpanded: Bool { expanded ?? isLatest }
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
            Button {
                // A large group is read on its own page, lazily, instead of growing this row by thousands of points.
                if item.operationCount > Self.inlineLimit { showingAll = true; return }
                // The reader is looking at this group: the page stays put while its height changes.
                holdPlace()
                // Not animated: an animated height change at the bottom of a running conversation moved the page.
                expanded = !isExpanded
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "book.pages")
                    if item.operationCount == 1 { Text(String(localized: "chat.activity_one")) }
                    else { Text(String.localizedStringWithFormat(String(localized: "chat.activity_count"), item.operationCount)) }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption.weight(.medium))
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("activity." + item.id).accessibilityValue(isExpanded ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if isExpanded {
                rows
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.messages.enumerated()), id: \.element.id) { index, message in
                            let row = MessageRow(message: message, projectRoot: projectRoot, openFile: openFile, images: images, openImage: openImage, openDetail: openDetail)
                            let previousIsOperation = index > 0 && MessageRow(message: item.messages[index - 1]).isOperation
                            row.padding(.top, index == 0 || (row.isOperation && previousIsOperation) ? 0 : 8)
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                }
                .navigationTitle(String.localizedStringWithFormat(String(localized: "chat.activity_count"), item.operationCount))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "page.close")) { showingAll = false } } }
            }
        }
        // The next message closes it, whatever the reader chose while it was the newest.
        .onChange(of: isLatest) { _, latest in
            if !latest { withAnimation(.easeInOut(duration: 0.18)) { expanded = nil } }
        }
    }
}
