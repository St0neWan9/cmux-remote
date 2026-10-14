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
    /// A pasted attachment is written to the terminal as its literal path; that path is not the agent's prose.
    @Test func aPastedAttachmentPathIsNotProse() {
        let screen = [
            "⏺ Reading the screenshot.",
            "'/Users/example/.local/state/cmux-remote/tui-images/cfec33dd24fa7dfa410e594a94d100aa6ed4e6108e0ad7ad45382608ab8f8037/944ec0379593ceaae1413f657c8d95612e8215b9f36f548ee1d44c4316fc516b/0.jpeg'",
            "✻ Blanching… (54s · ↓ 2.3k tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "Reading the screenshot.")
    }
    /// Prose that mentions the same directory is still the agent's own writing.
    @Test func proseMentioningTheImageStoreIsStillProse() {
        let screen = [
            "⏺ 图片缓存放在 tui-images 目录下，按会话和操作分两级哈希。",
            "✻ Thinking… (3s · ↓ 12 tokens)",
        ]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "图片缓存放在 tui-images 目录下，按会话和操作分两级哈希。")
    }
    /// Prose that merely starts with a dash is not a divider.
    @Test func proseIsNotMistakenForChrome() {
        let screen = ["⏺ - a hyphenated list item keeps its text.", "✻ Thinking… (3s · ↓ 12 tokens)"]
        let text = AgentChatProseScreenExtractor().extract(lines: screen, agentKind: .claude)
        #expect(text == "- a hyphenated list item keeps its text.")
    }
}
