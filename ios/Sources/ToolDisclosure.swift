import SwiftUI

/// Quiet tool rows reveal a full-width detail card without disclosure indentation.
struct ToolDisclosure<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 16)).frame(width: 20)
                    Text(title).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.medium))
                }.foregroundStyle(.secondary).frame(minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expanded ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if expanded { content().frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
