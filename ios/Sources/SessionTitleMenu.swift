import SwiftUI
import CmuxRemoteCore

/// The list's title opens the page's options: order, workspace, pending items, refresh and management.
struct SessionTitleMenu: View {
    @Binding var sortMode: SessionSortMode
    @Binding var workspaceID: String?
    let workspaces: [(id: String, title: String)]
    /// Macs whose pending items this device may read, with how many wait on each.
    let feeds: [(id: String, name: String, count: Int)]
    let canStart: Bool
    let showFeed: (String) -> Void
    let refresh: () -> Void
    let start: () -> Void
    let addMac: () -> Void
    var body: some View {
        Menu {
            Picker(String(localized: "sessions.sort"), selection: $sortMode) {
                ForEach(SessionSortMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
            }.pickerStyle(.inline)
            if workspaces.count > 1 {
                Picker(selection: $workspaceID) {
                    Text(String(localized: "sessions.all_workspaces")).tag(String?.none)
                    ForEach(workspaces, id: \.id) { workspace in Text(workspace.title).tag(String?.some(workspace.id)) }
                } label: { Label(String(localized: "sessions.workspace_filter"), systemImage: "macwindow") }
                    .pickerStyle(.menu)
            }
            Divider()
            if feeds.count == 1, let only = feeds.first {
                Button { showFeed(only.id) } label: { Label(feedTitle(only.count), systemImage: "bell") }
            } else if feeds.count > 1 {
                Menu {
                    ForEach(feeds, id: \.id) { feed in Button(feed.count > 0 ? "\(feed.name) (\(feed.count))" : feed.name) { showFeed(feed.id) } }
                } label: { Label(feedTitle(feeds.reduce(0) { $0 + $1.count }), systemImage: "bell") }
            }
            Button(action: refresh) { Label(String(localized: "sessions.refresh"), systemImage: "arrow.clockwise") }.accessibilityIdentifier("sessions.refresh")
            Section(String(localized: "sessions.manage")) {
                if canStart { Button(action: start) { Label(String(localized: "start.title"), systemImage: "plus") }.accessibilityIdentifier("sessions.start") }
                Button(action: addMac) { Label(String(localized: "pair.add_device"), systemImage: "laptopcomputer") }
            }
        } label: {
            HStack(spacing: 5) {
                Text(String(localized: "sessions.title")).font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.foregroundStyle(.primary).padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
        }.tint(.primary).accessibilityLabel(String(localized: "sessions.title_menu")).accessibilityIdentifier("sessions.title_menu")
    }
    private func feedTitle(_ count: Int) -> String {
        count > 0 ? String(format: String(localized: "feed.title_count"), count) : String(localized: "feed.title")
    }
}
