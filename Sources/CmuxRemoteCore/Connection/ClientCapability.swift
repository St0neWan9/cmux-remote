import Foundation

/// Separately granted resource capabilities. Terminal mirroring is not implemented by these grants.
public enum ClientCapability: String, Codable, Sendable, CaseIterable {
    case workspaceRead, conversationRead, projectRead, conversationControl, feedRead, feedReply
}
