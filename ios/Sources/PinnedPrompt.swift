import SwiftUI
import CmuxAgentChat
import CmuxRemoteCore

/// The prompt a sent bubble belongs to while the page holds it at the top.
///
/// The outgoing row exists only until the transcript records the prompt; the pin therefore also remembers the
/// text, which is what the recorded user row carries, so the page can hand the anchor over without moving.
struct PinnedPrompt: Equatable {
    /// The page's own foot below the rows, which the pinned prompt's tail leaves room for as well.
    static let foot: CGFloat = 18
    /// The coordinate space of the timeline's rows, in which the pinned row's top is measured.
    static let rowsSpace = "chatRows"
    /// The outgoing bubble, while it is still on the page.
    var outgoing: UUID?
    /// The text that identifies the recorded row once the bubble is gone.
    var text: String
    /// The recorded row that took the pin over: an earlier prompt with the same words is not the pinned one.
    var row: String? = nil
}

/// Whether a recorded user row carries the prompt a sent bubble showed.
enum PinnedPromptText {
    static func matches(_ message: ChatMessage, _ text: String) -> Bool {
        guard case .prose(let value) = message.kind else { return false }
        let wanted = normalize(PromptText.displayed(text))
        return !wanted.isEmpty && normalize(PromptText.displayed(value.text)).contains(wanted)
    }
    /// The same comparison the outgoing prompt matcher makes: whitespace runs do not change a prompt's text.
    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Reports a measurement while a prompt is pinned: the pinned row's top within the rows, or the rows' own height.
///
/// The room left under a pinned prompt is the page minus everything from that prompt down — its own row and the
/// running label, live preview and reply below it. Counting only the prompt's row let a running label that landed
/// under it grow the page, and the bottom anchor then pushed the prompt up under the header.
struct PinnedMeasureProbe: ViewModifier {
    enum Measure { case top, height }
    let active: Bool
    var measure: Measure = .top
    let report: (CGFloat) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if active {
            content.onGeometryChange(for: CGFloat.self) { geometry in
                measure == .top ? geometry.frame(in: .named(PinnedPrompt.rowsSpace)).minY : geometry.size.height
            } action: { value in
                if abs(value - last) > 0.5 { last = value; report(value) }
            }
        } else { content }
    }
    @State private var last: CGFloat = -1
}
