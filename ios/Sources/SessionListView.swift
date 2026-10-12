import SwiftUI
import CmuxRemoteCore

struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSidebar = false
    @State private var showSearch = false
    @State private var showConnection = false
    @State private var showFeed = false
    @State private var showConversation = false
    @State private var selectedSession: SessionDescriptor?
    @State private var pendingConnection = false
    @State private var pendingFeed = false
    @State private var pendingSession: SessionDescriptor?
    @State private var query = ""
    @State private var filter = SessionFilter.all
    @State private var workspaceID: String?
    var body: some View {
        let allSessions = model.sessions
        let workspaces = model.workspaces
        let sessions = allSessions.filter { filter.matches($0, query: query, workspaceID: workspaceID) }
        let groups = SessionProjectGroup.make(from: sessions)
        let client = model.client
        let loading = model.loading
        let error = model.error
        let host = model.host
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if showSearch || !query.isEmpty { SessionSearchField(query: $query) }
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
                    Menu {
                        Button(String(localized: "sessions.all_workspaces")) { workspaceID = nil }
                        ForEach(workspaces) { workspace in Button(workspace.title) { workspaceID = workspace.id } }
                    } label: {
                    Label(workspaces.first(where: { $0.id == workspaceID })?.title ?? host, systemImage: "laptopcomputer")
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.04), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.065), radius: 14, y: 4)
                    }.tint(.primary).accessibilityIdentifier("sessions.workspaces")
                    Text(String(localized: "sessions.projects")).font(.headline)
                    if let client {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                Label(group.name ?? String(localized: "sessions.other"), systemImage: "folder")
                                    .font(.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                ForEach(group.sessions) { session in
                                    NavigationLink {
                                        ConversationView(session: session, client: client, hostName: host)
                                    } label: { sessionRow(session) }
                                    .buttonStyle(.plain).accessibilityIdentifier("session." + session.id)
                                    .padding(.leading, 34)
                                }
                            }
                        }
                    }
                    if sessions.isEmpty && !loading {
                        Text(String(localized: client?.allows(.conversationRead) == false ? "sessions.no_read_grant" : (allSessions.isEmpty ? "sessions.empty" : "sessions.no_matches"))).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }
            .clipped()
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .onChange(of: workspaces.map(\.id)) { _, ids in if let workspaceID, !ids.contains(workspaceID) { self.workspaceID = nil } }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .overlay { if loading && sessions.isEmpty { ProgressView() } }
            .navigationDestination(isPresented: $showConversation) { if let selectedSession, let client { ConversationView(session: selectedSession, client: client, hostName: host) } }
            .navigationDestination(isPresented: $showConnection) { if let client { ConnectionDetailView(client: client, host: host, identity: model.hostIdentity, certificate: model.hostCertificate, endpoint: model.endpoint) { model.unpair() } } }
            .navigationDestination(isPresented: $showFeed) { if let client { FeedView(client: client) } }
            .fullScreenCover(isPresented: $showSidebar, onDismiss: {
                if let pendingSession { selectedSession = pendingSession; self.pendingSession = nil; showConversation = true }
                else if pendingConnection { pendingConnection = false; showConnection = true }
                else if pendingFeed { pendingFeed = false; showFeed = true }
            }) {
                NavigationStack {
                    SessionSidebarView(groups: groups, host: host, canReadFeed: client?.allows(.feedRead) ?? false, query: $query,
                        select: { pendingSession = $0; showSidebar = false },
                        showConnection: { pendingConnection = true; showSidebar = false }, showFeed: { pendingFeed = true; showSidebar = false },
                        refresh: { Task { await model.refresh() } })
                }.presentationBackground(.white).presentationDragIndicator(.hidden)
            }
        }.environment(\.colorScheme, .light)
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
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 3)
            }.buttonStyle(.plain).accessibilityLabel(String(localized: "sessions.sidebar")).accessibilityIdentifier("sessions.sidebar")
            Text(String(localized: "sessions.title")).font(.headline).frame(maxWidth: .infinity)
            Button { if showSearch || !query.isEmpty { showSearch = false; query = "" } else { showSearch = true } } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                    .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.07), radius: 12, y: 3)
            }.buttonStyle(.plain).accessibilityLabel(String(localized: "sessions.search")).accessibilityIdentifier("sessions.search")

        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
}
