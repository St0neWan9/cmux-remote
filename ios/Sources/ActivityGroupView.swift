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
    static let inlineLimit = ActivityGroupPolicy.inlineLimit
    @State private var showingAll = false
    /// The row this group belongs to, so expanding it keeps its place in the timeline.
    @Environment(\.holdPlace) private var holdPlace
    /// Whether the group is open inside the timeline. A group past the inline limit belongs on its own page even
    /// while it is the newest: a running Agent's group grows by the second, and one enormous row is what made the
    /// page stutter while it kept working. The summary row keeps counting, so the work is still visible.
    static func showsInline(operationCount: Int, isLatest: Bool, choice: Bool?) -> Bool {
        ActivityGroupPolicy.showsInline(operationCount: operationCount, isLatest: isLatest, choice: choice)
    }
    private var isExpanded: Bool { Self.showsInline(operationCount: item.operationCount, isLatest: isLatest, choice: expanded) }
    var body: some View {
        if item.operationCount == 0 {
            // Only reasoning, no operations: nothing to summarize, so it is shown directly.
            rows.frame(maxWidth: .infinity, alignment: .leading)
        } else { group }
    }
    /// Consecutive operations sit next to each other; reasoning text is set apart by a small gap.
    private var rows: some View {
        MessageRows(messages: item.messages, projectRoot: projectRoot, openFile: openFile, images: images,
                    openImage: openImage, openDetail: openDetail)
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
                    MessageRows(messages: item.messages, projectRoot: projectRoot, openFile: openFile, images: images,
                                openImage: openImage, openDetail: openDetail, lazy: true)
                        .padding(.horizontal, 14).padding(.vertical, 12)
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
