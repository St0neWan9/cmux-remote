import Foundation
import CmuxAgentChat

/// A bounded history page with a generation identifying transcript replacement.
public struct ConversationSnapshot: Codable, Sendable {
    public let messages: [ChatMessage]
    public let images: [ConversationImageReference]?
    public let hasMore: Bool
    public let generation: String
    public let clipped: Bool
    public let responses: [ConversationResponse]?
    public let recordedRunSeconds: Double?
    public let recordedTurnCount: Int?
    public let currentTurnStartedAt: Date?
    public let currentTurnCompleted: Bool?
    /// Tasks the agent detached and has not finished. They outlive the turn that started them.
    public let backgroundTasks: [BackgroundAgentTask]?
    /// Prompts waiting in the agent's queue while a turn runs; only the newest page carries them.
    public let queuedPrompts: [QueuedPrompt]?
    /// The model the transcript last reported; only the newest page carries it.
    public let agentModel: AgentModelState?
    public init(messages: [ChatMessage], hasMore: Bool, generation: String, clipped: Bool, responses: [ConversationResponse]? = nil, recordedRunSeconds: Double? = nil, recordedTurnCount: Int? = nil, currentTurnStartedAt: Date? = nil, currentTurnCompleted: Bool? = nil, images: [ConversationImageReference]? = nil, backgroundTasks: [BackgroundAgentTask]? = nil, queuedPrompts: [QueuedPrompt]? = nil, agentModel: AgentModelState? = nil) {
        self.images = images; self.messages = messages; self.hasMore = hasMore; self.generation = generation; self.clipped = clipped
        self.responses = responses; self.recordedRunSeconds = recordedRunSeconds; self.recordedTurnCount = recordedTurnCount
        self.currentTurnStartedAt = currentTurnStartedAt; self.currentTurnCompleted = currentTurnCompleted
        self.backgroundTasks = backgroundTasks; self.queuedPrompts = queuedPrompts; self.agentModel = agentModel
    }

    public func withQueuedPrompts(_ queuedPrompts: [QueuedPrompt]?) -> ConversationSnapshot {
        ConversationSnapshot(
            messages: messages, hasMore: hasMore, generation: generation, clipped: clipped,
            responses: responses, recordedRunSeconds: recordedRunSeconds, recordedTurnCount: recordedTurnCount,
            currentTurnStartedAt: currentTurnStartedAt, currentTurnCompleted: currentTurnCompleted,
            images: images, backgroundTasks: backgroundTasks, queuedPrompts: queuedPrompts, agentModel: agentModel
        )
    }
}
