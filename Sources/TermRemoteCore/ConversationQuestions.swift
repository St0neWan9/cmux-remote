import Foundation

/// The pending questions a conversation's agent is waiting on, keyed by the prompt its card shows.
///
/// The transcript records the question the agent asked but not the request that answers it; the Feed records
/// the request but not which card it belongs to. The prompt the agent wrote is what the two share, so it is
/// the key. Only a pending question naming this exact agent and session is matched: a question from another
/// conversation, or one already answered, must never make a card look answerable.
public struct ConversationQuestions: Sendable {
    /// One card's view of the request that answers it.
    ///
    /// A request that asked several questions is answered by one reply carrying one label per question, in
    /// the order they were asked, so a card must know the whole request: the first card carries the form for
    /// every question, and the later ones show it as a record rather than offering a short answer.
    public struct Match: Sendable, Equatable {
        public let requestID: String
        /// Every question the request asked, in the order the reply must answer them.
        public let questions: [JSONValue]
        /// This card's own question, within `questions`.
        public let index: Int
        public var isFirst: Bool { index == 0 }
        public var question: JSONValue { questions[index] }
    }
    public init() {}
    /// The questions that may be answered from this conversation, keyed by prompt.
    public func pending(_ items: [JSONValue], agent: String, sessionID: String) -> [String: Match] {
        let binding = FeedWorkspaceBinding()
        var matched: [String: Match] = [:]
        for item in items where item["kind"].string == "question" && item["status"].string == "pending" {
            guard let bound = binding.session(for: item), bound.agent == agent, bound.id == sessionID,
                  let requestID = item["request_id"].string else { continue }
            let questions = item["questions"].array ?? []
            for (index, question) in questions.enumerated() {
                guard let prompt = question["prompt"].string else { continue }
                matched[prompt] = Match(requestID: requestID, questions: questions, index: index)
            }
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
