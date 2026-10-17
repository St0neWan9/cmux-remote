import Foundation

/// The pending questions a conversation's agent is waiting on, keyed by the prompt its card shows.
///
/// The transcript records the question the agent asked but not the request that answers it; the Feed records
/// the request but not which card it belongs to. The prompt the agent wrote is what the two share, so it is
/// the key. Only a pending question naming this exact agent and session is matched: a question from another
/// conversation, or one already answered, must never make a card look answerable.
public struct ConversationQuestions: Sendable {
    public init() {}
    /// The questions that may be answered from this conversation, keyed by prompt.
    public func pending(_ items: [JSONValue], agent: String, sessionID: String) -> [String: JSONValue] {
        let binding = FeedWorkspaceBinding()
        var matched: [String: JSONValue] = [:]
        for item in items where item["kind"].string == "question" && item["status"].string == "pending" {
            guard let bound = binding.session(for: item), bound.agent == agent, bound.id == sessionID else { continue }
            // The Feed answers a request with one label per question it asked. A card shows one question, so
            // answering a request that asked several would send it a short answer; only a single question
            // is offered here, and the rest stay records until they are answered together in the Feed.
            let questions = item["questions"].array ?? []
            guard questions.count == 1, let question = questions.first, let prompt = question["prompt"].string else { continue }
            matched[prompt] = .object(["request_id": item["request_id"] ?? .null, "question": question])
        }
        return matched
    }
    /// The labels to send back for a card: one per question, in the order the card asked them.
    ///
    /// The Feed answers a pending request by label. An empty answer is meaningful only where the request
    /// offered no choices at all; a two-choice prompt is never answered by sending nothing.
    public func reply(requestID: String, selections: [String]) -> JSONValue {
        .object(["operation_id": .string(UUID().uuidString), "kind": .string("question"),
                 "selections": .array(selections.map(JSONValue.string)), "request_id": .string(requestID)])
    }
}
