import SwiftUI

/// Match the pale tool card: leading title/body and a quiet trailing result.
struct ToolDetailCard<Content: View>: View {
    let title: String
    var status: String?
    var failed = false
    @ViewBuilder let content: () -> Content
    /// Room for the content before it starts scrolling, and the height it takes when it does.
    private let maxContentHeight: CGFloat = 280
    private let minContentHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // A card grows with its output up to the ceiling, then scrolls; it is never taller or shorter than the content needs.
            if contentHeight > maxContentHeight {
                ClippedScroller(length: maxContentHeight, contentLength: contentHeight) { measured.fixedSize(horizontal: false, vertical: true) }
            } else {
                measured.frame(minHeight: minContentHeight, alignment: .top)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(MobileDesign.surfaceInset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius))
            .overlay(RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius).stroke(Color.black.opacity(0.035), lineWidth: 0.5))
    }
    /// The content, reporting what it wants so the card can decide between showing and scrolling it.
    private var measured: some View {
        content().frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - contentHeight) > 0.5 { contentHeight = height }
            }
    }
}
