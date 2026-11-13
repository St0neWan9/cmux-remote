import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSearch = false
    @State private var showConnection = false
    @State private var showFeed = false
    @State private var showConversation = false
    @State private var selectedConversation: ConversationModel?
    @State private var selectedHostName = ""
    @State private var connectionHostID: String?
    @State private var feedHostID: String?
    @State private var query = ""
    @State private var filter = SessionFilter.all
    @State private var workspaceID: String?
    /// The Mac whose conversations are shown; nil shows every Mac.
    @State private var hostFilter: String?
    @AppStorage(SessionSortMode.storageKey) private var sortMode = SessionSortMode.workspace
    /// The new-session sheet; a target is set when it was opened from one workspace's group.
    @State private var showStart = false
    /// The app's own page, opened from the list's title menu.
    @State private var showAbout = false
    @State private var startFrom: StartTarget?
    /// A terminal cmux just opened; the list waits for its conversation and then opens it.
    @State private var awaiting: AwaitedStart?
    @State private var startNotice: String?
    private struct AwaitedStart: Equatable { let hostID: String; let surfaceID: String?; let id = UUID() }
    /// Collapsed workspace groups, keyed by Mac and workspace; scene storage keeps them while other pages cover the list.
    @SceneStorage("sessions.collapsed") private var collapsedKeys = ""
    private var collapsed: Set<String> {
        get { Set(collapsedKeys.split(separator: "\n").map(String.init)) }
        nonmutating set { collapsedKeys = newValue.sorted().joined(separator: "\n") }
    }
    /// Lists whose earlier conversations the reader opened, keyed like the groups; remembered across launches.
    @AppStorage("sessions.earlierOpen") private var earlierOpenKeys = ""
    private var earlierOpen: Set<String> {
        get { Set(earlierOpenKeys.split(separator: "\n").map(String.init)) }
        nonmutating set { earlierOpenKeys = newValue.sorted().joined(separator: "\n") }
    }
    var body: some View {
        let links = model.links
        let workspaces = model.workspaces
        let shownLinks = hostFilter.map { id in links.filter { $0.id == id } } ?? links
        let hosted = model.hostedSessions.filter { (hostFilter == nil || $0.hostID == hostFilter) && filter.matches($0.session, query: query, workspaceID: workspaceID) }
        let sections = SessionHostSection.make(links: shownLinks, sessions: hosted, workspaces: workspaces)
        // The drawer lists every Mac's projects whichever Mac the list shows.
        let drawerSections = SessionHostSection.make(links: links, sessions: model.hostedSessions.filter { filter.matches($0.session, query: query, workspaceID: workspaceID) }, workspaces: workspaces)
        // Time order and a single selected workspace need no workspace headings.
        let grouped = workspaceID == nil && sortMode == .workspace
        // The Archive reads newest clear first; every other list by last activity.
        let archive = filter == .archived
        let order: (HostedSession) -> Date = { (archive ? $0.session.clearedAt : $0.session.updatedAt) ?? .distantPast }
        let recent = hosted.sorted { order($0) > order($1) }
        // A search or a status filter is the reader looking for something: every match shows, nothing folds.
        let folds = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter == .all
        let loading = model.loading
        let error = model.error
        let multiple = shownLinks.count > 1
        let canRead = links.contains { $0.client.allows(.conversationRead) }
        // The drawer stays as the user left it; a pushed page opens over it rather than closing it.
        SideDrawer(isPresented: $model.sidebarOpen, allowsEdgeOpening: !showConversation && !showConnection && !showFeed && !model.addingDevice) {
        AppNavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    HostFilterTabs(hosts: links.map { HostFilterTabs.Host(id: $0.id, name: $0.name, state: model.linkStates[$0.id], failed: model.hostErrors[$0.id] != nil, quiet: model.quietHosts.contains($0.id), workspaces: model.workspaces(of: $0.id)) },
                                   selection: $hostFilter, workspaceID: $workspaceID,
                                   move: { hostID, beforeID in model.move(hostID: hostID, beforeHostID: beforeID) })
                    PendingReminder(feed: PendingFeed.combined(pendingHosts(shownLinks).map { PendingFeed(count: $0.count, firstTitle: model.pending[$0.id]?.firstTitle) }),
                                    hosts: pendingHosts(shownLinks).filter { $0.count > 0 }) { id in feedHostID = id; showFeed = true }
                    // The status filter sits on the list it filters, under the Macs and what they wait on.
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(SessionFilter.allCases, id: \.rawValue) { value in
                            Button { filter = value } label: {
                                Text(value.localizedTitle)
                                    .font(.subheadline).foregroundStyle(filter == value ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(Color.white, in: Capsule())
                                    .shadow(color: .black.opacity(filter == value ? 0.06 : 0), radius: 10, y: 3)
                            }.buttonStyle(.plain).accessibilityIdentifier("sessions.filter." + value.rawValue)
                                .accessibilityAddTraits(filter == value ? .isSelected : [])
                        }
                    }
                    }
                    if let startNotice {
                        Label(startNotice, systemImage: awaiting == nil ? "checkmark.circle" : "hourglass")
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("sessions.start_notice")
                    }
                    // The Archive is one list in clear order, whatever order the others take.
                    if sortMode == .time || archive {
                        timeRows(recent, folds: folds, multiple: multiple)
                    } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                            if multiple {
                                Label(section.hostName, systemImage: "laptopcomputer").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                if let hostError = model.hostErrors[section.hostID] { Text(hostError).font(.footnote).foregroundStyle(.red) }
                            } else if grouped { Text(String(localized: "sessions.workspaces_title")).font(.headline) }
                            ForEach(section.groups) { group in
                                let key = section.hostID + "/" + group.id
                                VStack(alignment: .leading, spacing: 14) {
                                    if grouped {
                                        HStack(spacing: 0) {
                                        Button { toggle(key) } label: {
                                            HStack(spacing: 10) {
                                                Label(group.name ?? String(localized: "sessions.other"), systemImage: group.name == nil ? "clock.arrow.circlepath" : "macwindow")
                                                    .font(.body.weight(.semibold)).lineLimit(1)
                                                Spacer(minLength: 8)
                                            }.frame(minHeight: 36).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityAddTraits(.isHeader).accessibilityIdentifier("sessions.group." + key)
                                            .accessibilityValue(collapsed.contains(key) ? String(localized: "chat.collapsed") : String(localized: "chat.expanded"))
                                        // Starting a conversation here sits before the chevron and in its style, so the row
                                        // reads as one set of controls; the chevron keeps its own target and still collapses.
                                        if let target = model.startTargets.first(where: { $0.hostID == section.hostID && $0.workspace.id.lowercased() == group.id }) {
                                            Button { startFrom = target; showStart = true } label: {
                                                Image(systemName: "plus").font(.caption).foregroundStyle(.secondary)
                                                    .frame(width: 36, height: 36).contentShape(Rectangle())
                                            }.buttonStyle(.plain).accessibilityLabel(String(format: String(localized: "start.in_workspace"), group.name ?? ""))
                                                .accessibilityIdentifier("sessions.group." + key + ".start")
                                        }
                                        Button { toggle(key) } label: {
                                            Image(systemName: collapsed.contains(key) ? "chevron.right" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                                                .frame(width: 32, height: 36).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityLabel(String(localized: "sessions.group_toggle"))
                                            .accessibilityIdentifier("sessions.group." + key + ".toggle")
                                        }
                                    }
                                    if !grouped || !collapsed.contains(key) {
                                        groupRows(group.sessions, section: section, key: key, folds: folds, indented: grouped)
                                    }
                                }
                            }
                        }
                    }
                    }
                    if hosted.isEmpty && !loading {
                        let archiveEmpty = archive && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Text(String(localized: !canRead ? "sessions.no_read_grant" : (model.hostedSessions.isEmpty ? "sessions.empty" : (archiveEmpty ? "sessions.archive_empty" : "sessions.no_matches"))))
                            .foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    // The Mac's tab already says it is unreachable, and a Mac retried in the background is not shown
                    // as failing; the red line is for other failures.
                    if let error, !multiple, model.connectionState != .disconnected, model.quietHosts.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MobileDesign.pageInset).padding(.top, 20).padding(.bottom, 24)
            }
            .clipped()
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .onChange(of: workspaces.map(\.id)) { _, ids in if let workspaceID, !ids.contains(workspaceID) { self.workspaceID = nil } }
            .onChange(of: links.map(\.id)) { _, ids in if let hostFilter, !ids.contains(hostFilter) { self.hostFilter = nil } }
            // A workspace belongs to one Mac; choosing another Mac leaves it behind.
            .onChange(of: hostFilter) { _, id in
                if let id, let workspaceID, !model.workspaces(of: id).contains(where: { $0.id == workspaceID }) { self.workspaceID = nil }
            }
            // A pull reads again; only a Mac that is down is dialed again. The page menu keeps a full redial.
            .refreshable { await model.pullToRefresh() }
            .task { await model.refresh() }
            .overlay { if loading && hosted.isEmpty { ProgressView() } }
            .navigationDestination(isPresented: $showConversation) {
                if let selectedConversation {
                    // The page shows its Mac's link as the list does, so the two never disagree.
                    ConversationView(model: selectedConversation, hostName: selectedHostName,
                                     linkState: { model.shownLinkState(of: selectedConversation.client) },
                                     retryLink: { await model.reconnect(client: selectedConversation.client) })
                }
            }

            .navigationDestination(isPresented: $showFeed) { if let id = feedHostID, let link = model.link(for: id) { FeedView(client: link.client) } }
            .navigationDestination(isPresented: $showAbout) { AboutView() }

        }
        } drawer: {
            SessionSidebarView(sections: drawerSections, hosts: links.map { SidebarHost(id: $0.id, name: $0.name, failed: model.hostErrors[$0.id] != nil) },
                query: $query,
                recent: recent, sortMode: $sortMode,
                // The drawer stays open behind a pushed page, so coming back lands on it as it was.
                select: { hosted in model.sidebarOpen = false; openConversation(hosted) },
                showConnection: { id in connectionHostID = id; showConnection = true },
                addDevice: { model.addingDevice = true })
        }.environment(\.colorScheme, .light)
            // Presented over the drawer, which stays open behind them rather than squeezing them into its panel.
            .fullScreenCover(isPresented: $showConnection) {
                if let id = connectionHostID, let link = model.link(for: id) {
                    ConnectionDetailView(client: link.client, host: link.name, identity: link.connection?.host.id, certificate: link.connection?.host.certificateSHA256, endpoint: link.endpoint) {
                        showConnection = false; model.remove(hostID: id)
                    }
                }
            }
            .fullScreenCover(isPresented: $model.addingDevice) { PairingView(model: model) }
            .sheet(isPresented: $showStart, onDismiss: { startFrom = nil }) {
                StartSessionSheet(targets: model.startTargets, preselected: startFrom, multipleMacs: links.count > 1) { hostID, surfaceID in
                    startNotice = String(localized: "start.waiting"); awaiting = AwaitedStart(hostID: hostID, surfaceID: surfaceID)
                }
            }
            .task(id: awaiting) { await awaitStartedConversation() }
    }
    /// The agent reports its conversation a few seconds after its terminal opens; open it once it is listed.
    private func awaitStartedConversation() async {
        guard let awaited = awaiting else { return }
        for _ in 0..<20 {
            await model.refresh()
            if let surface = awaited.surfaceID,
               let found = model.hostedSessions.first(where: { $0.hostID == awaited.hostID && $0.session.surfaceID?.lowercased() == surface }) {
                awaiting = nil; startNotice = nil; openConversation(found); return
            }
            if awaited.surfaceID == nil { break }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
        }
        awaiting = nil; startNotice = String(localized: "start.opened")
    }
    private func openConversation(_ hosted: HostedSession) {
        diagLog(.info, category: "open", "tapped \(hosted.session.id.prefix(24)) state=\(hosted.session.state)")
        guard let link = model.link(for: hosted.hostID) else { return }
        selectedConversation = model.conversation(session: hosted.session, client: link.client)
        selectedHostName = hosted.hostName
        showConversation = true
    }
    private func scopeTitle(_ links: [HostLink]) -> String {
        links.count > 1 ? String(format: String(localized: "sessions.all_macs"), links.count) : (links.first?.name ?? model.host)
    }
    /// The time-ordered list: its recent conversations, then the fold that holds the rest.
    @ViewBuilder private func timeRows(_ recent: [HostedSession], folds: Bool, multiple: Bool) -> some View {
        let split = folds ? SessionRecency().split(recent, floor: SessionRecency.timeFloor) { $0.session } : (shown: recent, earlier: [])
        let open = earlierOpen.contains("time")
        ForEach(open ? recent : split.shown) { hosted in
            Button { openConversation(hosted) } label: { sessionRow(hosted.session, host: multiple ? hosted.hostName : nil) }
                .buttonStyle(.plain).accessibilityIdentifier("session." + hosted.hostID + "." + hosted.session.id)
        }
        if !split.earlier.isEmpty { earlierRow(count: split.earlier.count, open: open, key: "time") }
    }
    /// One workspace's conversations: its recent ones, then the fold that holds the rest.
    @ViewBuilder private func groupRows(_ sessions: [SessionDescriptor], section: SessionHostSection, key: String, folds: Bool, indented: Bool) -> some View {
        let split = folds ? SessionRecency().split(sessions, floor: SessionRecency.workspaceFloor) { $0 } : (shown: sessions, earlier: [])
        let open = earlierOpen.contains(key)
        ForEach(open ? sessions : split.shown) { session in
            Button { openConversation(HostedSession(hostID: section.hostID, hostName: section.hostName, session: session)) } label: { sessionRow(session) }
                .buttonStyle(.plain).accessibilityIdentifier("session." + section.hostID + "." + session.id)
                .padding(.leading, indented ? 34 : 0)
        }
        if !split.earlier.isEmpty { earlierRow(count: split.earlier.count, open: open, key: key).padding(.leading, indented ? 34 : 0) }
    }
    /// The fold under a list's recent conversations: it names how many earlier ones it holds and opens them in place.
    private func earlierRow(count: Int, open: Bool, key: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { if open { earlierOpen.remove(key) } else { earlierOpen.insert(key) } }
        } label: {
            HStack(spacing: 8) {
                Text(open ? String(localized: "sessions.earlier_hide")
                          : String.localizedStringWithFormat(String(localized: "sessions.earlier_show"), count))
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("sessions.earlier." + key)
        .accessibilityValue(open ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
    }
    private func toggle(_ key: String) {
        withAnimation(.easeInOut(duration: 0.18)) { if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) } }
    }
    private func sessionRow(_ session: SessionDescriptor, host: String? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(session.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let cleared = session.clearedAt {
                    Label(String(format: String(localized: "sessions.archived_at"), cleared.formatted(date: .abbreviated, time: .shortened)), systemImage: "archivebox")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(session.agent.capitalized)
                    if let host { Text(host).lineLimit(1) }
                    if let updated = session.updatedAt { Text(updated, format: .relative(presentation: .named)).lineLimit(1) }
                    // A conversation that can be reopened says so, rather than reading as plain history.
                    if session.resumable { Label(String(localized: "sessions.resume"), systemImage: "arrow.clockwise.circle") }
                    else if !session.writable { Label(String(localized: "sessions.read_only"), systemImage: "lock") }
                }.font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.state.hasPrefix("working") { WorkingIndicator() }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
    /// Macs whose pending items this device may read, among those shown.
    private func pendingHosts(_ links: [HostLink]) -> [(id: String, name: String, count: Int)] {
        links.filter { $0.client.allows(.feedRead) }.map { ($0.id, $0.name, model.pending[$0.id]?.count ?? 0) }
    }
    /// The drawer on the left, the page's options under its title and search on the right; searching takes the whole bar.
    private var header: some View {
        HStack(spacing: 12) {
            if showSearch || !query.isEmpty {
                SessionSearchField(query: $query, focusOnAppear: true)
                Button { showSearch = false; query = "" } label: { Image(systemName: "xmark") }
                    .floatingIconButton().accessibilityLabel(String(localized: "sessions.close_search")).accessibilityIdentifier("sessions.search.close")
            } else {
                Button { model.sidebarOpen = true } label: {
                    Image(systemName: "line.3.horizontal")
                }.floatingIconButton()
                    // The visible glass is smaller than the control; a tap a few points off still opens it.
                    .contentShape(Circle().inset(by: -8))
                    .accessibilityLabel(String(localized: "sessions.sidebar")).accessibilityIdentifier("sessions.sidebar")
                Spacer(minLength: 0)
                SessionTitleMenu(sortMode: $sortMode,
                                 feeds: pendingHosts(model.links), canStart: !model.startTargets.isEmpty,
                                 showFeed: { id in feedHostID = id; showFeed = true },
                                 refresh: { Task { await model.reconnect() } },
                                 start: { startFrom = nil; showStart = true },
                                 addMac: { model.addingDevice = true },
                                 about: { showAbout = true })
                Spacer(minLength: 0)
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }.floatingIconButton().accessibilityLabel(String(localized: "sessions.search")).accessibilityIdentifier("sessions.search")
            }
        }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 10)
    }
}
