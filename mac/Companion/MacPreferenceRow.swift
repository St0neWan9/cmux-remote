import SwiftUI

/// A right-aligned "Label:" and a leading control column; tables and images align to the label's top.
struct MacPreferenceRow<Content: View>: View {
    let title: String
    var topAligned = false
    @ViewBuilder let content: () -> Content
    private let design = MacDesignTokens()
    var body: some View {
        GridRow(alignment: topAligned ? .top : .firstTextBaseline) {
            Text(title.isEmpty ? "" : String(format: String(localized: "mac.label", bundle: .interface), title)).lineLimit(1)
                .padding(.top, topAligned ? design.labelTopPadding : 0).gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: design.rowSpacing, content: content)
                .frame(width: design.controlWidth, alignment: .leading)
        }
    }
}
