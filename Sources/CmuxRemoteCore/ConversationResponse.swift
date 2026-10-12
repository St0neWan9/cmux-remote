import Foundation

/// Presentation anchors and timing for one human prompt and its agent response.
public struct ConversationResponse: Codable, Sendable, Equatable {
    public let firstMessageID: String
    public let lastMessageID: String
    public let startedAt: Date?
    public let completedAt: Date?
    public let completed: Bool
    public let durationSeconds: Double?
    /// True only for a provider duration or explicit start/completion lifecycle pair.
    public let recordedDuration: Bool
    public let firstSeq: Int
    public let lastSeq: Int
    public init(firstMessageID: String, lastMessageID: String, startedAt: Date?, completedAt: Date?, durationSeconds: Double?, recordedDuration: Bool, completed: Bool = false, firstSeq: Int, lastSeq: Int) {
        self.firstMessageID = firstMessageID; self.lastMessageID = lastMessageID
        self.startedAt = startedAt; self.completedAt = completedAt; self.completed = completed; self.durationSeconds = durationSeconds
        self.recordedDuration = recordedDuration; self.firstSeq = firstSeq; self.lastSeq = lastSeq
    }
}
