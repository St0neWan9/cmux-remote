import SwiftUI

struct SessionListView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section(model.host) {
                    if model.sessions.isEmpty && !model.loading { Text(String(localized: "sessions.empty")).foregroundStyle(.secondary) }
                    ForEach(model.sessions) { session in
                        if let client = model.client {
                            NavigationLink {
                                ConversationView(session: session, client: client)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.title).lineLimit(2)
                                    HStack {
                                        Text(session.agent.capitalized)
                                        if !session.writable { Label(String(localized: "sessions.read_only"), systemImage: "lock") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                    if let cwd = session.cwd { Text(cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("session." + session.id)
                        }
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(String(localized: "sessions.title"))
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(String(localized: "pair.disconnect")) { model.unpair() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let client = model.client { NavigationLink { FeedView(client: client) } label: { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") } }
                }
            }
            .overlay { if model.loading && model.sessions.isEmpty { ProgressView() } }
        }
    }
}
