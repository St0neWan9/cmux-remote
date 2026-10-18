import Foundation

/// A numbered choice menu an Agent draws over its prompt, read from the rendered rows.
///
/// While one is open the prompt line is gone, but the Agent is still there waiting for the answer, so a terminal
/// showing a menu is neither a shell nor an empty prompt.
struct AgentMenuScreen: Sendable {
    let rows: [String]

    /// Whether the cursor rests on option 1 of a menu that offers at least a second option.
    var isShown: Bool {
        var cursor = false, second = false
        for row in rows {
            let body = Self.body(row)
            if let first = body.first, "❯›".contains(first), Self.numbered(body.dropFirst(), is: 1) { cursor = true }
            else if Self.numbered(body, is: 2) { second = true }
        }
        return cursor && second
    }

    /// Claude Code's confirmation before it re-reads a long cached conversation under another model.
    var asksToConfirmModelSwitch: Bool {
        isShown && rows.contains { Self.body($0).hasPrefix("Switch model?") }
    }

    private static func body(_ line: String) -> Substring {
        var value = line.drop(while: { $0 == " " || $0 == "\u{00a0}" })
        if value.hasPrefix("│") { value = value.dropFirst().drop(while: { $0 == " " || $0 == "\u{00a0}" }) }
        return value
    }

    /// `1. text`, after any spaces the cursor leaves in front of the number.
    private static func numbered(_ text: Substring, is number: Int) -> Bool {
        text.drop(while: { $0 == " " || $0 == "\u{00a0}" }).hasPrefix("\(number). ")
    }
}
