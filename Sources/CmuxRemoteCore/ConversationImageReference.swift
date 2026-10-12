import Foundation

/// An opaque image reference bound to a recorded message and transcript generation.
public struct ConversationImageReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messageID: String
    public let generation: String
    public let name: String
    public let requiresProjectRead: Bool
    public init(id: String, messageID: String, generation: String, name: String, requiresProjectRead: Bool) {
        self.id = id; self.messageID = messageID; self.generation = generation; self.name = name; self.requiresProjectRead = requiresProjectRead
    }
}
