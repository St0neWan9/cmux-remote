import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct ConversationView: View {
    @State private var model: ConversationModel
    @Environment(\.scenePhase) private var phase
    init(session: SessionDescriptor, client: RemoteClient) { _model = State(initialValue: ConversationModel(session: session, client: client)) }
    var body: some View {
        List {
            if model.hasMore { Button(String(localized: "chat.older")) { Task { await model.older() } } }
            ForEach(model.messages) { message in MessageRow(message: message) }
            if let preview = model.preview {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "chat.preview"), systemImage: "ellipsis.bubble").font(.caption).foregroundStyle(.secondary)
                    Text(preview).textSelection(.enabled)
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(model.session.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { NavigationLink { ProjectView(session: model.session, client: model.client) } label: { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !model.canSend { Text(String(localized: "sessions.read_only")).font(.caption).foregroundStyle(.secondary) }
                HStack(alignment: .bottom) {
                    TextField(String(localized: "chat.prompt"), text: $model.draft, axis: .vertical).lineLimit(1...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("chat.composer")
                    Button { Task { await model.send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.accessibilityLabel(String(localized: "chat.send"))
                        .accessibilityIdentifier("chat.send").disabled(model.busy || !model.canSend || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { Task { await model.interrupt() } } label: { Image(systemName: "stop.circle") }.accessibilityLabel(String(localized: "chat.stop")).disabled(model.busy || !model.canSend)
                }
            }.padding().background(.regularMaterial)
        }
        .refreshable { await model.refresh() }
        .task(id: phase) {
            guard phase == .active else { return }
            await model.refresh()
            // Compatibility cadence for local APIs without chat subscriptions; cancellation ends it.
            let ticker = RefreshTicker(); defer { ticker.stop() }
            for await _ in ticker.start() {
                guard !Task.isCancelled else { break }; await model.refresh()
            }
        }
    }
}
