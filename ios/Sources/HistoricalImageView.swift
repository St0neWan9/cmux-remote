import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// A white native preview with explicit copy/share actions; no host URL is opened.
struct HistoricalImageView: View {
    @State private var model: HistoricalImageModel
    @State private var image: UIImage?
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    init(reference: ConversationImageReference, sessionID: String, client: RemoteClient) {
        _model = State(initialValue: HistoricalImageModel(reference: reference, fetch: { try await client.image(sessionID: sessionID, reference: reference) }))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel(model.reference.name)
                    HStack {
                        Button { UIPasteboard.general.image = image } label: { Label(String(localized: "project.copy"), systemImage: "doc.on.doc") }
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(model.reference.name, image: Image(uiImage: image))) { Label(String(localized: "project.share"), systemImage: "square.and.arrow.up") }
                    }.buttonStyle(FloatingButtonStyle())
                } else if model.loading { ProgressView() }
                else if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button(String(localized: "chat.refresh")) { Task { await model.load() } }.buttonStyle(FloatingButtonStyle())
                }
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                .navigationTitle(model.reference.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "image.close")) { dismiss() } } }
        }.environment(\.colorScheme, .light)
        .onChange(of: model.data) { _, value in image = value.flatMap(UIImage.init(data:)) }
        .onDisappear { model.suspend() }
        .onChange(of: phase) { _, value in if value != .active { model.suspend() } }
        .task(id: phase) { guard phase == .active else { return }; await model.load() }
    }
}
