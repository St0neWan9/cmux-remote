import Foundation
import SwiftTerm
import CmuxRemoteCore

/// Bounded daemon VT state decoded only on the Bridge, including faint prompt placeholders.
struct TuiTerminalState: Sendable {
    let rows: [String]
    let typedRows: [String]
    let pasteEnabled: Bool
    init(_ payload: JSONValue) throws {
        guard let columns = payload["cols"].int, (1...500).contains(columns), let count = payload["rows"].int, (1...200).contains(count),
              let encoded = payload["state_base64"].string, encoded.utf8.count <= 1_398_104,
              let data = Data(base64Encoded: encoded), data.count <= 1_048_576 else { throw BridgeError("invalid_response", "The daemon terminal state is invalid.", status: 502) }
        // Canonical grid replays need no graphics payloads; keep decode-only parsing bounded.
        let raw = String(decoding: data, as: UTF8.self)
        guard !raw.contains("\u{1b}P"), !raw.contains("\u{1b}_"), !raw.contains("\u{90}"), !raw.contains("\u{9f}") else { throw BridgeError("unsupported", "This terminal replay contains unsupported graphics/control payloads.", status: 422) }
        let sink = TuiTerminalSink(), terminal = Terminal(delegate: sink, options: TerminalOptions(cols: columns, rows: count, scrollback: 0, enableSixelReported: false, kittyImageCacheLimitBytes: 0))
        terminal.feed(byteArray: Array(data))
        var plain: [String] = [], visible: [String] = []
        for row in 0..<count {
            var text = "", nonFaint = ""
            for col in 0..<columns {
                guard let cell = terminal.getCharData(col: col, row: row), cell.width != 0 else { continue }
                let character = terminal.getCharacter(for: cell), value = character == "\0" ? " " : String(character)
                text += value
                nonFaint += cell.attribute.style.contains(.dim) ? String(repeating: " ", count: max(1, Int(cell.width))) : value
            }
            plain.append(text); visible.append(nonFaint)
        }
        rows = plain; typedRows = visible; pasteEnabled = terminal.bracketedPasteMode
    }
}
