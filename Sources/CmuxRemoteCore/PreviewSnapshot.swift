import Foundation

/// A replaceable preview, never a committed history message.
public struct PreviewSnapshot: Codable, Sendable {
    public let text: String?
    public let available: Bool
    /// Whether the agent is compacting its context right now. Optional so an older Bridge, which does
    /// not report it, still decodes instead of failing the whole read.
    public let compacting: Bool?
    public init(text: String?, available: Bool, compacting: Bool? = nil) {
        self.text = text; self.available = available; self.compacting = compacting
    }
}
