import Foundation
import Testing
@testable import TermRemoteBridge

/// Claude shows a suggested next prompt as faint text in its empty input box. Only a styled
/// screen tells it apart from a draft the person typed and has not sent.
@Suite struct StyledPromptSafetyTests {
    private func state(_ screen: String) throws -> TuiTerminalState {
        try TuiTerminalState(columns: 40, rows: 6, vt: Data(screen.utf8))
    }
    private let rule = "\u{1b}[38;2;136;136;136m────────────────────\u{1b}[0m\r\n"

    @Test func aFaintSuggestionIsAnEmptyPrompt() throws {
        let screen = rule + "\u{1b}[38;2;153;153;153m❯\u{a0}\u{1b}[0m\u{1b}[2m拉个 ubuntu 镜像试试\u{1b}[0m\r\n" + rule
        #expect(TuiPromptSafety().isEmpty(try state(screen), provider: "claude"))
        // The same row as plain text reads as a draft, which is the failure this replaces.
        let plain = try state(screen).rows.joined(separator: "\n")
        #expect(!TuiPromptSafety().isEmpty(plain, provider: "claude"))
    }

    @Test func typedTextIsStillADraft() throws {
        let screen = rule + "❯\u{a0}half a sentence\r\n" + rule
        #expect(!TuiPromptSafety().isEmpty(try state(screen), provider: "claude"))
    }

    @Test func typedTextAfterAFaintSuggestionIsStillADraft() throws {
        let screen = rule + "❯\u{a0}draft \u{1b}[2msuggested rest\u{1b}[0m\r\n" + rule
        #expect(!TuiPromptSafety().isEmpty(try state(screen), provider: "claude"))
    }

    @Test func anOpenQuestionStillBlocksTyping() throws {
        let screen = "❯\u{a0}\u{1b}[2mnext step\u{1b}[0m\r\n" + rule + "Enter to confirm · Esc to cancel\r\n"
        #expect(!TuiPromptSafety().isEmpty(try state(screen), provider: "claude"))
    }

    @Test func scrollbackAboveTheScreenIsDropped() throws {
        // Rex's vt format writes scrollback first; only the final screen decides.
        let history = (0..<20).map { "❯\u{a0}old typed line \($0)\r\n" }.joined()
        let screen = history + rule + "❯\u{a0}\u{1b}[2mnext\u{1b}[0m\r\n" + rule
        #expect(TuiPromptSafety().isEmpty(try state(screen), provider: "claude"))
    }
}
