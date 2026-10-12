import SwiftUI

/// One centered grid: the label column is as wide as its longest label, controls keep their native size.
struct MacPreferencePage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    private let design = MacDesignTokens()
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: design.labelSpacing, verticalSpacing: design.groupSpacing, content: content)
            .padding(.vertical, design.verticalInset)
            .frame(width: design.windowWidth)
    }
}
