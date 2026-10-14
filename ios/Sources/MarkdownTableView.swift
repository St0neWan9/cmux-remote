import SwiftUI
import CmuxRemoteCore

/// A pipe table drawn as a grid; a table wider than the message scrolls sideways inside it.
struct MarkdownTableView: View {
    let table: MarkdownTable
    /// Long cells wrap at this width so one column cannot push the others off screen.
    private let maxColumnWidth: CGFloat = 240
    @State private var available: CGFloat = 0
    @State private var natural: CGSize = .zero
    /// Each column's widest single-line cell, so a column is only as wide as it needs and wraps past the cap.
    @State private var columnWidths: [Int: CGFloat] = [:]
    var body: some View {
        // The table sits in an overlay so its natural width can never widen the message;
        // the placeholder takes the message width and the table's measured height.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: natural.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .overlay(alignment: .topLeading) {
                if natural.width > available + 0.5, available > 0 {
                    ClippedScroller(.horizontal, length: available, contentLength: natural.width) { grid }
                } else {
                    grid
                }
            }
    }
    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(table.header.indices, id: \.self) { column in cell(table.header[column], column: column, header: true) }
            }
            .background(Color.black.opacity(0.04))
            ForEach(table.rows.indices, id: \.self) { row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(table.rows[row].indices, id: \.self) { column in cell(table.rows[row][column], column: column, header: false) }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
    }
    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        let font: Font = header ? .subheadline.weight(.semibold) : .subheadline
        let frameAlignment: SwiftUI.Alignment = alignment == .center ? .center : alignment == .trailing ? .trailing : .leading
        // A fixed column width lets a wrapped cell report its real height to the row.
        return Text(.init(text))
            .font(font)
            .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
            .frame(width: min(maxColumnWidth, columnWidths[column] ?? maxColumnWidth), alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                Text(.init(text)).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        if width > (columnWidths[column] ?? 0) { columnWidths[column] = width }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .textSelection(.enabled)
    }
}
