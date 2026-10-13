import SwiftUI

/// Match the pale tool card: leading title/body and a quiet trailing result.
struct ToolDetailCard<Content: View>: View {
    let title: String
    var status: String?
    var failed = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Short output keeps its natural height; long output scrolls inside a fixed-height card.
            ViewThatFits(in: .vertical) {
                content().frame(maxWidth: .infinity, alignment: .leading)
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }.scrollBounceBehavior(.basedOnSize)
            }.frame(maxHeight: 280)
            if let status {
                Text(status).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(MobileDesign.surfaceInset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius))
            .overlay(RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius).stroke(Color.black.opacity(0.035), lineWidth: 0.5))
    }
}
