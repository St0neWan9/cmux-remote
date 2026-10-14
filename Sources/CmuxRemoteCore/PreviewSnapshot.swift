import Foundation

/// A replaceable preview, never a committed history message.
public struct PreviewSnapshot: Codable, Sendable {
    public let text: String?
    public let available: Bool
    /// The agent's own working line from the terminal, when it is rendering one.
    public let status: TuiAgentStatus?
    public init(text: String?, available: Bool, status: TuiAgentStatus? = nil) {
        self.text = text; self.available = available; self.status = status
    }
}
