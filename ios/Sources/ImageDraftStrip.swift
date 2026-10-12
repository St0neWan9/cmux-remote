import SwiftUI
import CmuxRemoteCore

/// Immutable image snapshots keep typing and polling from re-decoding thumbnails.
struct ImageDraftStrip: View, Equatable {
    nonisolated let images: [ChatImagePayload]
    let remove: (UUID) -> Void
    @State private var preview: ChatImagePayload?
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.images.map(\.id) == rhs.images.map(\.id) }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        Button { preview = image } label: {
                            if let data = Data(base64Encoded: image.dataBase64), let thumbnail = UIImage(data: data) {
                                Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }.buttonStyle(.plain).accessibilityLabel(String(localized: "image.preview") + " " + image.fileName)
                            .accessibilityIdentifier("image.draft.\(image.id)")
                        Button { remove(image.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 28).background(.white, in: Circle()).shadow(radius: 3)
                        }.buttonStyle(.plain).accessibilityLabel(String(localized: "image.remove"))
                            .offset(x: 6, y: -6)
                    }
                }
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }
        .navigationDestination(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let image = preview {
                WhitePage(title: String(localized: "image.preview")) {
                    if let data = Data(base64Encoded: image.dataBase64), let decoded = UIImage(data: data) {
                        Image(uiImage: decoded).resizable().scaledToFit().padding(MobileDesign.pageInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}
