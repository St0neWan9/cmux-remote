import SwiftUI
import CmuxRemoteCore

/// A white project drawer receives immutable discovery snapshots, never a live store under its lazy rows.
struct SessionSidebarView: View {
    let sections: [SessionHostSection]
    let hosts: [SidebarHost]
    /// All matching conversations, newest activity first, for the time arrangement.
    let recent: [HostedSession]
    @Binding var sortMode: SessionSortMode
    @Binding var query: String
    let select: (HostedSession) -> Void
    let showConnection: (String) -> Void
    let addDevice: () -> Void
    @State private var showSearch = false
    @State private var expanded: Set<String>
    @State private var initializedExpansion: Bool
    init(sections: [SessionHostSection], hosts: [SidebarHost], query: Binding<String>, recent: [HostedSession], sortMode: Binding<SessionSortMode>, select: @escaping (HostedSession) -> Void, showConnection: @escaping (String) -> Void, addDevice: @escaping () -> Void) {
        self.sections = sections; self.hosts = hosts; self.recent = recent; _sortMode = sortMode; _query = query
        self.select = select; self.showConnection = showConnection; self.addDevice = addDevice
        let first = sections.first.flatMap { section in section.groups.first.map { section.hostID + "/" + $0.id } }
        _expanded = State(initialValue: Set(first.map { [$0] } ?? []))
        _initializedExpansion = State(initialValue: first != nil)
    }
    var body: some View {
        let multiple = hosts.count > 1
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(localized: "app.title")).font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Picker(String(localized: "sessions.sort"), selection: $sortMode) {
                        ForEach(SessionSortMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 19)).frame(width: 44, height: 44) }
                    .tint(.primary).accessibilityLabel(String(localized: "sessions.sort")).accessibilityIdentifier("sidebar.sort")
                Button { withAnimation { showSearch.toggle() } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 21)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "sessions.search"))
                    .accessibilityIdentifier("sidebar.search")
            }.padding(.horizontal, MobileDesign.pageInset).padding(.top, 8).padding(.bottom, 14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    if showSearch || !query.isEmpty { SessionSearchField(query: $query) }
                    if sortMode == .time {
                        Text(String(localized: "sessions.recent")).font(.headline)
                        ForEach(recent) { hosted in
                            Button { select(hosted) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hosted.session.title).lineLimit(2)
                                        if multiple { Text(hosted.hostName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if hosted.session.state.hasPrefix("working") { WorkingIndicator(size: 13) }
                                    else if !hosted.session.writable { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("sidebar.session." + hosted.hostID + "." + hosted.session.id)
                        }
                    } else {
                        ForEach(sections) { section in
                            Text(multiple ? section.hostName : String(localized: "sessions.workspaces_title")).font(.headline).lineLimit(1)
                            ForEach(section.groups) { group in projectGroup(group, section: section) }
                        }
                    }
                    if sections.isEmpty { Text(String(localized: "sessions.no_matches")).foregroundStyle(.secondary) }
                }.padding(.horizontal, MobileDesign.pageInset).padding(.top, 16).padding(.bottom, 28)
            }.onChange(of: query) { _, value in
                if !value.isEmpty { expanded.formUnion(sections.flatMap { section in section.groups.map { section.hostID + "/" + $0.id } }) }
            }
            VStack(spacing: 2) {
                ForEach(hosts) { host in
                    Button { showConnection(host.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: host.failed ? "exclamationmark.triangle" : "laptopcomputer").font(.system(size: 20))
                                .foregroundStyle(host.failed ? Color.red : Color.primary)
                            Text(host.name).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "gearshape").font(.system(size: 19)).frame(width: 40, height: 40)
                                .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.07), radius: 12, y: 3)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("sidebar.connection." + host.id)
                }
                Button(action: addDevice) {
                    Label(String(localized: "pair.add_device"), systemImage: "plus.circle").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(MobileDesign.accent).accessibilityIdentifier("sidebar.add_device")
            }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 12)
        }.background(Color.white.ignoresSafeArea())
            .onChange(of: sections.map(\.id)) { _, _ in
                if !initializedExpansion, let section = sections.first, let group = section.groups.first { expanded.insert(section.hostID + "/" + group.id); initializedExpansion = true }
            }
    }
    private func projectGroup(_ group: SessionWorkspaceGroup, section: SessionHostSection) -> some View {
        let key = section.hostID + "/" + group.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.name == nil ? "clock.arrow.circlepath" : "macwindow").font(.system(size: 20))
                    Text(group.name ?? String(localized: "sessions.other")).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("sidebar.project." + key)
                .accessibilityValue(expanded.contains(key) ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if expanded.contains(key) {
                ForEach(group.sessions) { session in
                    Button { select(HostedSession(hostID: section.hostID, hostName: section.hostName, session: session)) } label: {
                        HStack {
                            Text(session.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if session.state.hasPrefix("working") { WorkingIndicator(size: 13) }
                            else if !session.writable { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.leading, 34).accessibilityIdentifier("sidebar.session." + section.hostID + "." + session.id)
                }
            }
        }
    }
}
