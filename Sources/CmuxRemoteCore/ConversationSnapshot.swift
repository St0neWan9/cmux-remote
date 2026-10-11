import Foundation
import CmuxAgentChat

/// A bounded history page with a generation identifying transcript replacement.
public struct ConversationSnapshot: Codable, Sendable {
    public let messages: [ChatMessage]
    public let hasMore: Bool
    public let generation: String
    public let clipped: Bool
    public init(messages: [ChatMessage], hasMore: Bool, generation: String, clipped: Bool) {
        self.messages = messages; self.hasMore = hasMore; self.generation = generation; self.clipped = clipped
    }
}
