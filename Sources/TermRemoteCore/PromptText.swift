import Foundation

/// What the reader sent, without the wrapper an agent's CLI records around pasted text.
///
/// The phone hands a prompt to the agent as a paste, and Claude Code records a pasted multi-line prompt as
/// `<pasted_content id="…">…</pasted_content id="…">`. Shown as recorded, the reader's own bubble carried the
/// tags, and a sent prompt no longer matched the message that recorded it.
public enum PromptText {
    public static func displayed(_ text: String) -> String {
        guard text.contains("<pasted_content") else { return text }
        // Built per call: a Regex is not Sendable, and this runs only for the rare wrapped prompt.
        let opening = #/<pasted_content id="[^"<>\n]{0,64}">\n?/#
        let closing = #/\n?</pasted_content(?: id="[^"<>\n]{0,64}")?>/#
        let unwrapped = text.replacing(opening, with: "").replacing(closing, with: "")
        return unwrapped == text ? text : unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
