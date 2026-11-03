import Foundation

/// Separately granted resource capabilities; terminal viewing and input are independent.
public enum ClientCapability: String, Codable, Sendable, CaseIterable {
    case workspaceRead, conversationRead, projectRead, conversationControl, feedRead, feedReply
    case terminalRead, terminalInput
    /// Opens a new terminal running a fixed agent command in an already-approved workspace.
    case conversationStart
}
