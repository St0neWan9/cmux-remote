import Foundation
import CmuxAgentChat

/// A prompt this phone sent that the transcript has not recorded yet; the page shows it until the agent writes it down.
public struct OutgoingPrompt: Identifiable, Sendable, Equatable {
    public enum Delivery: Sendable, Equatable {
        /// The Bridge has not answered the send yet.
        case sending
        /// The Bridge accepted the send; the agent has not written it to its transcript yet.
        case sent
        /// The send outcome is unknown; the prompt may or may not have reached the agent.
        case unconfirmed
    }
    /// The send's operation ID, so a later receipt or acknowledgement finds the same prompt.
    public let id: UUID
    public let text: String
    public let imageCount: Int
    public var delivery: Delivery
    /// The history the prompt was sent after: only user messages recorded later can be this prompt.
    let generation: String?
    let afterSeq: Int?
    let knownUserIDs: Set<String>
    public init(request: SendRequest, after messages: [ChatMessage], generation: String?, delivery: Delivery = .sending) {
        id = request.operationID; text = request.text; imageCount = request.attachments.count; self.delivery = delivery
        self.generation = generation; afterSeq = messages.last?.seq
        knownUserIDs = Set(messages.filter { $0.role == .user }.map(\.id))
    }
}
