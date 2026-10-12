import Foundation

/// A replaceable preview, never a committed history message.
public struct PreviewSnapshot: Codable, Sendable {
    public let text: String?
    public let available: Bool
    public init(text: String?, available: Bool) { self.text = text; self.available = available }
}
