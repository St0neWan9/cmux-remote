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
    /// The outgoing bubble, while it is still on the page.
    var outgoing: UUID?
    /// The text that identifies the recorded row once the bubble is gone.
    var text: String
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

/// Reports a pinned row's height: the tail's size is the page minus that height, so it comes from the row.
struct PinnedHeightProbe: ViewModifier {
    let pinned: Bool
    let report: (CGFloat) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if pinned {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - lastHeight) > 0.5 { lastHeight = height; report(height) }
            }
        } else { content }
    }
    @State private var lastHeight: CGFloat = 0
}
