import SwiftUI

/// Quiet tool rows reveal a full-width detail card without disclosure indentation.
struct ToolDisclosure<Content: View>: View {
    let title: String
    let symbol: String
    var identifier = "tool.disclosure"
    @ViewBuilder let content: () -> Content
    @Environment(\.holdPlace) private var holdPlace
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                // The reader is looking at this card: the page stays put while its height changes.
                holdPlace()
                // Not animated: an animated height change inside an open group moved the scroll view by hundreds
                // of points the moment the card was tapped.
                expanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 16)).frame(width: 20)
                    Text(title).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.medium))
                }.foregroundStyle(.secondary).frame(minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityValue(expanded ? String(localized: "chat.expanded") : String(localized: "chat.collapsed"))
            if expanded { content().frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
