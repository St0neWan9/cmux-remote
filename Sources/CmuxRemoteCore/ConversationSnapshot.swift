import Foundation
import CmuxAgentChat

/// A bounded history page with a generation identifying transcript replacement.
public struct ConversationSnapshot: Codable, Sendable {
    public let messages: [ChatMessage]
    public let hasMore: Bool
    public let generation: String
    public let clipped: Bool
    public let responses: [ConversationResponse]?
    public let recordedRunSeconds: Double?
    public let recordedTurnCount: Int?
    public let currentTurnStartedAt: Date?
    public let currentTurnCompleted: Bool?
    public init(messages: [ChatMessage], hasMore: Bool, generation: String, clipped: Bool, responses: [ConversationResponse]? = nil, recordedRunSeconds: Double? = nil, recordedTurnCount: Int? = nil, currentTurnStartedAt: Date? = nil, currentTurnCompleted: Bool? = nil) {
        self.messages = messages; self.hasMore = hasMore; self.generation = generation; self.clipped = clipped
        self.responses = responses; self.recordedRunSeconds = recordedRunSeconds; self.recordedTurnCount = recordedTurnCount
        self.currentTurnStartedAt = currentTurnStartedAt; self.currentTurnCompleted = currentTurnCompleted
    }
}
