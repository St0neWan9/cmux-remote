import Foundation

/// A prompt accepted while the agent is still running a turn and waiting in its input queue.
///
/// Published by the Bridge on the newest history page so every connected device sees the same
/// queue above the composer until the transcript records the prompt as a user message.
public struct QueuedPrompt: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let queuedAt: Date?

    public init(id: String, text: String, queuedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.queuedAt = queuedAt
    }
}
