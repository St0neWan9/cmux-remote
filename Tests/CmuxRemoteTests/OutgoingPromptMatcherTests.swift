import Foundation
import Testing
import CmuxAgentChat
import CmuxRemoteCore

@Suite struct OutgoingPromptMatcherTests {
    private func user(_ id: String, _ seq: Int, _ text: String) -> ChatMessage {
        ChatMessage(id: id, seq: seq, role: .user, timestamp: Date(timeIntervalSince1970: 0), kind: .prose(ChatProse(text: text)))
    }
    private func agent(_ id: String, _ seq: Int, _ text: String) -> ChatMessage {
        ChatMessage(id: id, seq: seq, role: .agent, timestamp: Date(timeIntervalSince1970: 0), kind: .prose(ChatProse(text: text)))
    }
    @Test func aPromptStaysUntilTheTranscriptRecordsItAfterTheSend() {
        let history = [user("old", 0, "continue"), agent("reply", 1, "Done")]
        let prompt = OutgoingPrompt(request: SendRequest(text: "continue"), after: history, generation: "g1")
        // The earlier identical prompt is not this one.
        #expect(OutgoingPromptMatcher().pending([prompt], messages: history, generation: "g1") == [prompt])
        let recorded = history + [user("new", 2, "continue")]
        #expect(OutgoingPromptMatcher().pending([prompt], messages: recorded, generation: "g1").isEmpty)
    }
    @Test func onlyAMessageRecordedAfterTheSendCanReplaceIt() {
        let history = [agent("reply", 5, "Done")]
        let prompt = OutgoingPrompt(request: SendRequest(text: "fix it"), after: history, generation: "g1")
        // An older page loaded later is not new, though the phone had not seen it at send time.
        let paged = [user("older", 2, "fix it")] + history
        #expect(OutgoingPromptMatcher().pending([prompt], messages: paged, generation: "g1") == [prompt])
    }
    @Test func eachTranscriptMessageReplacesOnlyOneOfTwoIdenticalPrompts() {
        let history = [agent("reply", 1, "Done")]
        let first = OutgoingPrompt(request: SendRequest(text: "go on"), after: history, generation: "g1")
        let second = OutgoingPrompt(request: SendRequest(text: "go on"), after: history, generation: "g1")
        let pending = OutgoingPromptMatcher().pending([first, second], messages: history + [user("a", 2, "go on")], generation: "g1")
        #expect(pending == [second])
    }
    @Test func textMatchesWinOverRecordingOrderAndRewrittenPromptsStillMatch() {
        let history = [agent("reply", 1, "Done")]
        let photo = OutgoingPrompt(request: SendRequest(text: "", attachments: [ChatImagePayload(fileName: "a.jpg", format: "jpeg", data: Data([1]))]), after: history, generation: "g1")
        let typed = OutgoingPrompt(request: SendRequest(text: "look at\nthis"), after: history, generation: "g1")
        let recorded = history + [user("b", 2, "[Image #1] look at this"), user("c", 3, "[Image #1]")]
        #expect(OutgoingPromptMatcher().pending([photo, typed], messages: recorded, generation: "g1").isEmpty)
    }
    @Test func aReplacedHistoryOnlyMatchesOnText() {
        let history = [user("old", 0, "start"), agent("reply", 1, "Done")]
        let prompt = OutgoingPrompt(request: SendRequest(text: "next step"), after: history, generation: "g1")
        // A new history window re-reads earlier prompts with new positions; none of them is this prompt.
        let replaced = [user("earlier", 0, "something else"), agent("reply2", 1, "Done")]
        #expect(OutgoingPromptMatcher().pending([prompt], messages: replaced, generation: "g2") == [prompt])
        #expect(OutgoingPromptMatcher().pending([prompt], messages: replaced + [user("new", 2, "next step")], generation: "g2").isEmpty)
    }
}
