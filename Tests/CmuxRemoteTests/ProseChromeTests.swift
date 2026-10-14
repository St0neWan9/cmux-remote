import Foundation
import Testing
import CmuxAgentChat

/// The preview must show what the agent wrote, never the terminal's own chrome around it.
@Suite struct ProseChromeTests {
    /// The composer's frame, a CLI notice, and the divider rows Claude draws around its input box
    /// all sit within reach of the upward walk from the working line.
    @Test func composerChromeNeverReachesThePreview() {
        let screen = [
            "⏺ The table now fits the message width.",
            "✔ Update installed · Restart to update",
            "╭──────────────────────────────────────╮",
            "│ ❯                                    │",
            "╰──────────────────────────────────────╯",
            "✻ Blanching… (54s · ↓ 2.3k tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "The table now fits the message width.")
    }
    /// The box is stepped over, so the answer above it still reads normally.
    @Test func aScreenAnchoredBelowTheComposerStillReadsTheAnswer() {
        let screen = [
            "⏺ The answer sits above the input box.",
            "╭──────────────────────────────────────╮",
            "│ ❯                                    │",
            "╰──────────────────────────────────────╯",
            "esc to interrupt",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "The answer sits above the input box.")
    }
    /// A CLI notice is never part of the agent's prose.
    @Test func aNoticeLineIsNotPartOfThePreview() {
        let screen = [
            "⏺ Earlier work.",
            "✔ Update installed · Restart to update",
            "⏺ The current answer.",
            "✻ Thinking… (3s · ↓ 12 tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "The current answer.")
    }
    /// Claude Code's status bar carries the git branch, which is not the agent's prose.
    @Test func theBranchStatusBarIsNotProse() {
        let screen = [
            "⏺ The table now fits the message width.",
            "⏵⏵ auto mode on · ⎇ main",
            "✻ Blanching… (54s · ↓ 2.3k tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "The table now fits the message width.")
    }
    /// A branch name alone, without the marker, is still chrome.
    @Test func aBareBranchRowIsNotProse() {
        let screen = [
            "⏺ The answer.",
            "⎇ main",
            "✻ Thinking… (3s · ↓ 12 tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "The answer.")
    }
    /// Prose that merely starts with a dash is not a divider.
    @Test func proseIsNotMistakenForChrome() {
        let screen = ["⏺ - a hyphenated list item keeps its text.", "✻ Thinking… (3s · ↓ 12 tokens)"]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "- a hyphenated list item keeps its text.")
    }
}
