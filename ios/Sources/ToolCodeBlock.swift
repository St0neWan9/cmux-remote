import SwiftUI

/// Leading code preserves whitespace and scrolls long output inside the card.
struct ToolCodeBlock: View {
    let text: String
    @ScaledMetric(relativeTo: .callout) private var lineHeight = 22
    var body: some View {
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            Text(text).font(.system(.callout, design: .monospaced)).lineSpacing(2)
                .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
        }.defaultScrollAnchor(.topLeading).frame(height: min(264, CGFloat(max(1, lineCount)) * lineHeight))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
