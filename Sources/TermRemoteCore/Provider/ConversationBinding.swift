import Foundation

/// Proof that an Agent conversation currently runs in one terminal. A binding
/// is produced only by the provider that proved it; transcript paths and raw
/// provider ids stay inside the Bridge.
public struct ConversationBinding: Codable, Sendable, Equatable {
    public let conversationID: String
    public let providerID: String
    public let spaceID: String
    public let terminalID: String
    public let agent: String
    /// "cmux_registry", "daemon_hook", "agent_hook", "claude_registry" or "antigravity_presence".
    public let proof: String
    public let observedAt: Date

    public init(conversationID: String, providerID: String, spaceID: String, terminalID: String,
                agent: String, proof: String, observedAt: Date = Date()) {
        self.conversationID = conversationID; self.providerID = providerID; self.spaceID = spaceID
        self.terminalID = terminalID; self.agent = agent; self.proof = proof; self.observedAt = observedAt
    }
}
