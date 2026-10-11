import SwiftUI
import CmuxRemoteCore

struct SessionListView: View {
    @Bindable var model: AppModel
    var body: some View {
        let sessions = model.sessions
        let groups = SessionProjectGroup.make(from: sessions)
        let client = model.client
        let loading = model.loading
        let error = model.error
        let host = model.host
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    Label(host, systemImage: "laptopcomputer")
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.04), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.065), radius: 14, y: 4)
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
                        Text(String(localized: "sessions.empty")).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }
            .clipped()
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .overlay { if loading && sessions.isEmpty { ProgressView() } }
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
            Menu {
                Button { Task { await model.refresh() } } label: { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }
                Button { model.unpair() } label: { Label(String(localized: "pair.disconnect"), systemImage: "link") }
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 3)
            }.tint(.primary).accessibilityLabel(String(localized: "sessions.options")).accessibilityIdentifier("sessions.options")
            Text(String(localized: "sessions.title")).font(.headline).frame(maxWidth: .infinity)
            if let client = model.client {
                NavigationLink { FeedView(client: client).toolbar(.visible, for: .navigationBar) } label: {
                    Image(systemName: "checkmark.bubble").font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.07), radius: 12, y: 3)
                }.tint(.primary).accessibilityLabel(String(localized: "feed.title")).accessibilityIdentifier("sessions.feed")
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
}
