import Foundation
import Testing
import CmuxRemoteCore

/// A conversation's cards answer only where the Feed holds a matching pending request.
@Suite struct ConversationQuestionsTests {
    private func workstream(agent: String = "claude", session: String = "session-a") -> String {
        "cmux-feed-v1:" + Data(agent.utf8).base64EncodedString() + ":" + Data(session.utf8).base64EncodedString()
    }
    private func item(requestID: String = "req-1", status: String = "pending", kind: String = "question",
                      agent: String = "claude", session: String = "session-a",
                      prompts: [String] = ["用哪个方案?"]) -> JSONValue {
        .object(["request_id": .string(requestID), "kind": .string(kind), "status": .string(status), "workstream_id": .string(workstream(agent: agent, session: session)),
                 "questions": .array(prompts.map { .object(["prompt": .string($0), "options": .array([.object(["id": .string("a"), "label": .string("方案一")])])]) })])
    }
    @Test func onlyAPendingSingleQuestionOfThisConversationIsOffered() {
        let matcher = ConversationQuestions()
        let offered = matcher.pending([item()], agent: "claude", sessionID: "session-a")
        #expect(offered["用哪个方案?"]?["request_id"].string == "req-1")
        #expect(offered["用哪个方案?"]?["question"]["prompt"].string == "用哪个方案?")
        // Another conversation's question, an answered one, or another kind never makes a card answerable.
        #expect(matcher.pending([item()], agent: "claude", sessionID: "session-b").isEmpty)
        #expect(matcher.pending([item()], agent: "codex", sessionID: "session-a").isEmpty)
        #expect(matcher.pending([item(status: "resolved")], agent: "claude", sessionID: "session-a").isEmpty)
        #expect(matcher.pending([item(status: "expired")], agent: "claude", sessionID: "session-a").isEmpty)
        #expect(matcher.pending([item(kind: "permissionRequest")], agent: "claude", sessionID: "session-a").isEmpty)
    }
    @Test func aRequestThatAskedSeveralQuestionsIsAnsweredInTheFeed() {
        // One label per question is what the Feed expects; a card answers one, so it offers none.
        #expect(ConversationQuestions().pending([item(prompts: ["第一个?", "第二个?"])], agent: "claude", sessionID: "session-a").isEmpty)
        // Distinct single-question requests both appear, each keyed by its own prompt.
        let mine = ConversationQuestions().pending([item(requestID: "r1", prompts: ["一?"]), item(requestID: "r2", prompts: ["二?"])], agent: "claude", sessionID: "session-a")
        #expect(Set(mine.keys) == ["一?", "二?"])
        #expect(mine["一?"]?["request_id"].string == "r1")
        #expect(mine["二?"]?["request_id"].string == "r2")
    }
    @Test func anUnknownWorkstreamIsNeverMatched() {
        let unbound: JSONValue = .object(["request_id": .string("req-1"), "kind": .string("question"), "status": .string("pending"),
                                          "questions": .array([.object(["prompt": .string("一?")])])])
        #expect(ConversationQuestions().pending([unbound], agent: "claude", sessionID: "session-a").isEmpty)
        // A workstream naming a different provider is a different conversation, never a match by prompt alone.
        #expect(ConversationQuestions().pending([item(agent: "codex")], agent: "claude", sessionID: "session-a").isEmpty)
    }
    @Test func aReplyCarriesOneOperationAndItsLabels() {
        let body = ConversationQuestions().reply(requestID: "req-1", selections: ["继续"])
        #expect(body["kind"].string == "question")
        #expect(body["request_id"].string == "req-1")
        #expect(body["selections"].array?.compactMap(\.string) == ["继续"])
        // A fresh operation each time: the Bridge's ledger rejects a repeated one with a different payload.
        #expect(body["operation_id"].string != ConversationQuestions().reply(requestID: "req-1", selections: ["继续"])["operation_id"].string)
        #expect((body["operation_id"].string.flatMap { UUID(uuidString: $0) }) != nil)
    }
}
