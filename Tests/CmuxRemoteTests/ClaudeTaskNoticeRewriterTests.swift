import Foundation
import Testing
import CmuxAgentChat
@testable import CmuxRemoteBridge

@Suite struct ClaudeTaskNoticeRewriterTests {
    private func parse(_ lines: [String]) -> [ChatMessage] {
        ClaudeTranscriptParser().parse(lines: ClaudeTaskNoticeRewriter().normalize(lines), startingSeq: 0).messages
    }
    @Test func aTaskNoticeIsNotThePersonsPrompt() {
        let notice = #"{"type":"user","uuid":"n1","timestamp":"2026-10-13T10:00:00Z","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>abc</task-id>\n</task-notification>"}}"#
        let prompt = #"{"type":"user","uuid":"u1","timestamp":"2026-10-13T10:00:01Z","message":{"role":"user","content":"actual question"}}"#
        let messages = parse([notice, prompt])
        #expect(messages.map(\.id) == ["u1"])
        #expect(messages.first?.kind == .prose(ChatProse(text: "actual question")))
    }
    @Test func ordinaryRecordsAndOtherOriginsAreLeftAlone() {
        let pasted = #"{"type":"user","uuid":"p1","timestamp":"2026-10-13T10:00:00Z","message":{"role":"user","content":"<pasted_content id=\"a1\">a pasted block</pasted_content>"}}"#
        let other = #"{"type":"user","uuid":"o1","timestamp":"2026-10-13T10:00:01Z","origin":{"kind":"human"},"message":{"role":"user","content":"typed by the person"}}"#
        #expect(parse([pasted, other]).map(\.id) == ["p1", "o1"])
        let untouched = #"{"type":"system","subtype":"turn_duration"}"#
        #expect(ClaudeTaskNoticeRewriter().normalize(untouched) == untouched)
    }
}
