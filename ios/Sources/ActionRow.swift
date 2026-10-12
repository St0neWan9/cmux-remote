import SwiftUI

/// Actions wrap into a vertical group when labels no longer fit on one line.
struct ActionRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MobileDesign.rowGap, content: content).fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: MobileDesign.rowGap, content: content)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
