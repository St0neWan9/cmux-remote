import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSidebar = false
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
    var body: some View {
        let links = model.links
        let workspaces = model.workspaces
        let hosted = model.hostedSessions.filter { filter.matches($0.session, query: query, workspaceID: workspaceID) }
        let sections = SessionHostSection.make(links: links, sessions: hosted)
        let loading = model.loading
        let error = model.error
        let multiple = links.count > 1
        let canRead = links.contains { $0.client.allows(.conversationRead) }
        SideDrawer(isPresented: $showSidebar, allowsEdgeOpening: !showConversation && !showConnection && !showFeed) {
        AppNavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    if showSearch || !query.isEmpty { SessionSearchField(query: $query) }
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
                    Menu {
                        Button(String(localized: "sessions.all_workspaces")) { workspaceID = nil }
                        ForEach(workspaces) { workspace in Button(workspaceTitle(workspace, multiple: multiple)) { workspaceID = workspace.id } }
                    } label: {
                    Label(workspaces.first(where: { $0.id == workspaceID }).map { workspaceTitle($0, multiple: multiple) } ?? scopeTitle(links), systemImage: multiple ? "laptopcomputer.and.iphone" : "laptopcomputer")
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.04), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.065), radius: 14, y: 4)
                    }.tint(.primary).accessibilityIdentifier("sessions.workspaces")
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                            if multiple {
                                Label(section.hostName, systemImage: "laptopcomputer").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                if let hostError = model.hostErrors[section.hostID] { Text(hostError).font(.footnote).foregroundStyle(.red) }
                            } else { Text(String(localized: "sessions.projects")).font(.headline) }
                            ForEach(section.groups) { group in
                                VStack(alignment: .leading, spacing: 14) {
                                    Label(group.name ?? String(localized: "sessions.other"), systemImage: "folder")
                                        .font(.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                    ForEach(group.sessions) { session in
                                        Button { openConversation(HostedSession(hostID: section.hostID, hostName: section.hostName, session: session)) } label: { sessionRow(session) }
                                        .buttonStyle(.plain).accessibilityIdentifier("session." + section.hostID + "." + session.id)
                                        .padding(.leading, 34)
                                    }
                                }
                            }
                        }
                    }
                    if hosted.isEmpty && !loading {
                        Text(String(localized: !canRead ? "sessions.no_read_grant" : (model.hostedSessions.isEmpty ? "sessions.empty" : "sessions.no_matches"))).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    if let error, !multiple { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MobileDesign.pageInset).padding(.top, 20).padding(.bottom, 24)
            }
            .clipped()
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .onChange(of: workspaces.map(\.id)) { _, ids in if let workspaceID, !ids.contains(workspaceID) { self.workspaceID = nil } }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .onDisappear { showSidebar = false }
            .overlay { if loading && hosted.isEmpty { ProgressView() } }
            .navigationDestination(isPresented: $showConversation) { if let selectedConversation { ConversationView(model: selectedConversation, hostName: selectedHostName) } }
            .navigationDestination(isPresented: $showConnection) {
                if let id = connectionHostID, let link = model.link(for: id) {
                    ConnectionDetailView(client: link.client, host: link.name, identity: link.connection?.host.id, certificate: link.connection?.host.certificateSHA256, endpoint: link.endpoint) {
                        showConnection = false; model.remove(hostID: id)
                    }
                }
            }
            .navigationDestination(isPresented: $showFeed) { if let id = feedHostID, let link = model.link(for: id) { FeedView(client: link.client) } }
        }
        } drawer: {
            SessionSidebarView(sections: sections, hosts: links.map { SidebarHost(id: $0.id, name: $0.name, canReadFeed: $0.client.allows(.feedRead), failed: model.hostErrors[$0.id] != nil) },
                query: $query,
                select: { hosted in showSidebar = false; openConversation(hosted) },
                showConnection: { id in showSidebar = false; connectionHostID = id; showConnection = true },
                showFeed: { id in showSidebar = false; feedHostID = id; showFeed = true },
                addDevice: { showSidebar = false; model.addingDevice = true },
                refresh: { Task { await model.refresh() } })
        }.environment(\.colorScheme, .light)
    }
    private func openConversation(_ hosted: HostedSession) {
        guard let link = model.link(for: hosted.hostID) else { return }
        selectedConversation = model.conversation(session: hosted.session, client: link.client)
        selectedHostName = hosted.hostName
        showConversation = true
    }
    private func scopeTitle(_ links: [HostLink]) -> String {
        links.count > 1 ? String(format: String(localized: "sessions.all_macs"), links.count) : (links.first?.name ?? model.host)
    }
    private func workspaceTitle(_ workspace: WorkspaceSummary, multiple: Bool) -> String {
        guard multiple, let host = model.workspaceHosts[workspace.id] else { return workspace.title }
        return workspace.title + " · " + host
    }
    private func sessionRow(_ session: SessionDescriptor) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(session.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 8) {
                    Text(session.agent.capitalized)
                    if !session.writable { Label(String(localized: "sessions.read_only"), systemImage: "lock") }
                }.font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.state.hasPrefix("working") { ProgressView().controlSize(.small) }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { showSidebar = true } label: {
                Image(systemName: "line.3.horizontal")
            }.buttonStyle(FloatingIconStyle()).accessibilityLabel(String(localized: "sessions.sidebar")).accessibilityIdentifier("sessions.sidebar")
            Text(String(localized: "sessions.title")).font(.headline).frame(maxWidth: .infinity)
            Button { if showSearch || !query.isEmpty { showSearch = false; query = "" } else { showSearch = true } } label: {
                Image(systemName: "magnifyingglass")
            }.buttonStyle(FloatingIconStyle()).accessibilityLabel(String(localized: "sessions.search")).accessibilityIdentifier("sessions.search")

        }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 10)
    }
}
