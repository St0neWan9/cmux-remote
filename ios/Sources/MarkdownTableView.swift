import SwiftUI
import CmuxRemoteCore

/// A pipe table as wide as its message: rows divided by hairlines, columns wrapping their text,
/// and a sideways scroll only when the columns cannot wrap any narrower.
struct MarkdownTableView: View {
    let table: MarkdownTable
    private let gap: CGFloat = 16
    @State private var available: CGFloat = 0
    @State private var height: CGFloat = 0
    var body: some View {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let metrics = MarkdownTableMetrics(table: table, body: font, header: .systemFont(ofSize: font.pointSize, weight: .semibold))
        let widths = metrics.widths(available: available, gap: gap)
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
        // The table sits in an overlay so its width can never widen the message;
        // the placeholder takes the message width and the table's measured height.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .overlay(alignment: .topLeading) {
                if available > 0 {
                    if total > available + 0.5 {
                        ClippedScroller(.horizontal, length: available, contentLength: total) { grid(widths) }
                    } else {
                        grid(widths)
                    }
                }
            }
    }
    private func grid(_ widths: [CGFloat]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: gap, verticalSpacing: 0) {
            GridRow {
                ForEach(table.header.indices, id: \.self) { column in cell(table.header[column], column: column, width: widths[column], header: true) }
            }
            ForEach(table.rows.indices, id: \.self) { row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(table.rows[row].indices, id: \.self) { column in cell(table.rows[row][column], column: column, width: widths[column], header: false) }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }
    private func cell(_ text: String, column: Int, width: CGFloat, header: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        let frameAlignment: SwiftUI.Alignment = alignment == .center ? .center : alignment == .trailing ? .trailing : .leading
        // A fixed column width lets a wrapped cell report its real height to the row.
        return Text(styled(text))
            .font(header ? .subheadline.weight(.semibold) : .subheadline)
            .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
            .frame(width: width, alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
            .textSelection(.enabled)
    }
    /// Inline Markdown with code spans dimmed, as they read in the desktop transcript.
    private func styled(_ markdown: String) -> AttributedString {
        var value = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true { value[run.range].foregroundColor = .secondary }
        return value
    }
}
