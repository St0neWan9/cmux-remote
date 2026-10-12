import SwiftUI

/// Classic macOS preferences: one right-aligned label column and one control column.
struct MacSettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title.isEmpty ? "" : title + ":").lineLimit(1).fixedSize(horizontal: false, vertical: true)
                .frame(width: MacDesignTokens().labelWidth, alignment: .trailing).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8, content: content).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
