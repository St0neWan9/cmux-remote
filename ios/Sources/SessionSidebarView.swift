import SwiftUI
import CmuxRemoteCore

/// A white project drawer receives immutable discovery snapshots, never a live store under its lazy rows.
struct SessionSidebarView: View {
    let groups: [SessionProjectGroup]
    let host: String
    let canReadFeed: Bool
    @Binding var query: String
    let select: (SessionDescriptor) -> Void
    let showConnection: () -> Void
    let showFeed: () -> Void
    let refresh: () -> Void
    @State private var showSearch = false
    @State private var expanded: Set<String>
    @State private var initializedExpansion: Bool
    init(groups: [SessionProjectGroup], host: String, canReadFeed: Bool, query: Binding<String>, select: @escaping (SessionDescriptor) -> Void, showConnection: @escaping () -> Void, showFeed: @escaping () -> Void, refresh: @escaping () -> Void) {
        self.groups = groups; self.host = host; self.canReadFeed = canReadFeed; _query = query
        self.select = select; self.showConnection = showConnection; self.showFeed = showFeed; self.refresh = refresh
        _expanded = State(initialValue: Set(groups.prefix(1).map(\.id)))
        _initializedExpansion = State(initialValue: !groups.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(localized: "app.title")).font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { showSearch.toggle() } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 21)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "sessions.search"))
                    .accessibilityIdentifier("sidebar.search")
            }.padding(.horizontal, MobileDesign.pageInset).padding(.top, 8).padding(.bottom, 14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    if showSearch || !query.isEmpty { SessionSearchField(query: $query) }
                    Text(String(localized: "sessions.projects")).font(.headline)
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder").font(.system(size: 22))
                                    Text(group.name ?? String(localized: "sessions.other")).font(.body.weight(.semibold))
                                    Spacer()
                                    Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("sidebar.project." + group.id)
                                .accessibilityValue(expanded.contains(group.id) ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
                            if expanded.contains(group.id) {
                                ForEach(group.sessions) { session in
                                    Button { select(session) } label: {
                                        HStack {
                                            Text(session.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            if session.state.hasPrefix("working") { ProgressView().controlSize(.mini) }
                                            else if !session.writable { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).padding(.leading, 34).accessibilityIdentifier("sidebar.session." + session.id)
                                }
                            }
                        }
                    }
                    if groups.isEmpty { Text(String(localized: "sessions.no_matches")).foregroundStyle(.secondary) }
                    if canReadFeed { Button(action: showFeed) { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") }.buttonStyle(FloatingButtonStyle()) }
                    Button(action: refresh) { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }.buttonStyle(FloatingButtonStyle())
                }.padding(.horizontal, MobileDesign.pageInset).padding(.top, 16).padding(.bottom, 28)
            }.onChange(of: query) { _, value in if !value.isEmpty { expanded.formUnion(groups.map(\.id)) } }
            Button(action: showConnection) {
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer").font(.system(size: 20))
                    Text(host).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "gearshape").font(.system(size: 21)).frame(width: 44, height: 44)
                        .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.07), radius: 12, y: 3)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("sidebar.connection")
                .padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 12)
        }.background(Color.white.ignoresSafeArea())
            .onChange(of: groups.map(\.id)) { _, ids in
                if !initializedExpansion, let first = ids.first { expanded.insert(first); initializedExpansion = true }
            }
    }
}
