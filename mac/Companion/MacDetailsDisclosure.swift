import SwiftUI

/// Collapsed details do not publish empty hidden accessibility groups.
struct MacDetailsDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                Label(title, systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.callout).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityValue(String(localized: expanded ? "mac.details.expanded" : "mac.details.collapsed"))
            if expanded { content() }
        }
    }
}
