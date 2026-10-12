import Foundation

/// Local companion policy: crops a captured grid while keeping its visible cursor in view.
public struct MobileTerminalGridViewport: Sendable {
    public init() {}
    public func fit(_ source: MobileTerminalRenderGridFrame, columns: Int, rows: Int) -> MobileTerminalRenderGridFrame {
        let width = max(1, min(columns, source.columns)), height = max(1, min(rows, source.rows))
        guard width != source.columns || height != source.rows else { return source }
        let cursor = source.cursor.flatMap { $0.visible ? $0 : nil }
        let top = min(source.rows - height, max(0, (cursor?.row ?? 0) - max(0, height - 3)))
        let left = min(source.columns - width, max(0, (cursor?.column ?? 0) - max(0, width - 3)))
        var frame = source
        frame.columns = width; frame.rows = height
        frame.rowSpans = source.rowSpans.flatMap { span -> [MobileTerminalRenderGridFrame.RowSpan] in
            guard (top..<(top + height)).contains(span.row) else { return [] }
            let characters = Array(span.text)
            var widths = characters.map(\.renderGridEstimatedCellWidth)
            let target = span.cellWidth ?? widths.reduce(0, +)
            var difference = target - widths.reduce(0, +)
            for index in widths.indices where difference > 0 && widths[index] == 1 && characters[index].canExpandForAmbiguousRenderGridWidth {
                widths[index] = 2; difference -= 1
            }
            for index in widths.indices.reversed() where difference < 0 && widths[index] == 2 {
                widths[index] = 1; difference += 1
            }
            guard difference == 0 else { return [] }
            var column = span.column, output: [MobileTerminalRenderGridFrame.RowSpan] = []
            for (index, character) in characters.enumerated() {
                let cells = widths[index]
                if cells > 0, column >= left, column + cells <= left + width {
                    output.append(.init(row: span.row - top, column: column - left, styleID: span.styleID,
                        text: String(character), cellWidth: cells))
                }
                column += cells
            }
            return output
        }
        if var position = frame.cursor {
            position.row = min(height - 1, max(0, position.row - top))
            position.column = min(width - 1, max(0, position.column - left))
            frame.cursor = position
        }
        frame.clearedRows = Array(0..<height)
        frame.scrollbackRows = 0; frame.scrollbackSpans = []; frame.scrolledRows = 0
        return frame
    }
}
