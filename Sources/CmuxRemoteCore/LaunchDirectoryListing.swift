import Foundation

/// The visible subdirectories of one folder inside a launch root.
public struct LaunchDirectoryListing: Codable, Sendable, Equatable {
    public let rootID: String
    /// Relative to the root; empty for the root itself.
    public let path: String
    public let directories: [String]
    /// True when more subdirectories exist than were returned.
    public let truncated: Bool
    public init(rootID: String, path: String, directories: [String], truncated: Bool) {
        self.rootID = rootID; self.path = path; self.directories = directories; self.truncated = truncated
    }
    private enum CodingKeys: String, CodingKey { case path, directories, truncated; case rootID = "root_id" }
}
