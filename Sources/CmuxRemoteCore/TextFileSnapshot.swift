import Foundation

/// A constrained UTF-8 project file or unified diff.
public struct TextFileSnapshot: Codable, Sendable {
    public let path: String
    public let text: String
    public let truncated: Bool
    public init(path: String, text: String, truncated: Bool) { self.path = path; self.text = text; self.truncated = truncated }
}
