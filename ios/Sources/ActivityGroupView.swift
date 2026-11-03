import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// Details stay accessible behind one quiet summary instead of filling the conversation with cards.
struct ActivityGroupView: View {
    let item: ConversationTimelineItem
    var projectRoot: String?
    var openFile: ((String) -> Void)?
    var images: [ConversationImageReference] = []
    var openImage: ((ConversationImageReference) -> Void)?
    var openDetail: ((String, String) -> Void)?
    /// The conversation an image or a tool page belongs to. This group's own sheet presents them itself: a page
    /// pushed by the conversation behind it opens underneath the sheet that asked for it.
    var sessionID = ""
    var client: RemoteClient?
    var generation: String?
    /// Whether this group is the newest item in the conversation. The newest group opens on its own so its
    /// work can be followed as it happens, and closes once the next message arrives.
    var isLatest = false
    /// The reader's own choice, which wins until the group stops being the newest.
    @State private var expanded: Bool?
    /// Groups past this many operations draw only their newest slice here; the rest is read on their own page.
    static let inlineLimit = ActivityGroupPolicy.inlineLimit
    @State private var showingAll = false
    @State private var sheetImage: ConversationImageReference?
    @State private var sheetDetail: ToolDetailReference?
    /// The row this group belongs to, so expanding it keeps its place in the timeline.
    @Environment(\.holdPlace) private var holdPlace
    /// The group stays open while it is the newest, so a running Agent stays readable, but a long one draws only
    /// its newest slice: one enormous row is what made the page stutter and left a blank page behind a collapse.
    private var isExpanded: Bool { ActivityGroupPolicy.isExpanded(isLatest: isLatest, choice: expanded) }
    private var drawsWhole: Bool { ActivityGroupPolicy.drawsWhole(operationCount: item.operationCount) }
    var body: some View {
        if item.operationCount == 0 {
            // Only reasoning, no operations: nothing to summarize, so it is shown directly.
            rows.frame(maxWidth: .infinity, alignment: .leading)
        } else { group }
    }
    /// Consecutive operations sit next to each other; reasoning text is set apart by a small gap.
    private var rows: some View {
        let shown = drawsWhole ? item.messages : Array(item.messages.suffix(ActivityGroupPolicy.windowMessages))
        return MessageRows(messages: shown, projectRoot: projectRoot, openFile: openFile, images: images,
                           openImage: openImage, openDetail: openDetail)
    }
    private var group: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                // A long group is read on its own page, lazily; the row here only ever draws its newest slice.
                if !drawsWhole { showingAll = true; return }
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
                                openImage: { reference in
                                    if let client, !sessionID.isEmpty { sheetImage = reference } else { openImage?(reference) }
                                },
                                openDetail: { messageID, field in
                                    if let client, let generation { sheetDetail = ToolDetailReference(messageID: messageID, generation: generation, initialField: field) }
                                    else { openDetail?(messageID, field) }
                                }, lazy: true)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                // A cover rather than a push: pushing inside the sheet slides the page underneath it, which shows
                // as the operations page jumping up and settling back when the image closes.
                .fullScreenCover(isPresented: Binding(get: { sheetImage != nil }, set: { if !$0 { sheetImage = nil } })) {
                    if let reference = sheetImage, let client { HistoricalImageView(reference: reference, sessionID: sessionID, client: client) }
                }
                .fullScreenCover(isPresented: Binding(get: { sheetDetail != nil }, set: { if !$0 { sheetDetail = nil } })) {
                    if let reference = sheetDetail, let client { ToolDetailView(reference: reference, sessionID: sessionID, client: client) }
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
