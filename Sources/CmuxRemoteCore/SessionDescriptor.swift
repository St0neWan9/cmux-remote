import Foundation

/// A supported conversation; a verified binding is required for writes.
public struct SessionDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let agent: String
    public let title: String
    public let cwd: String?
    public var workspaceID: String?
    public var surfaceID: String?
    public var state: String
    /// Last activity: when the conversation's transcript was last written. Older Bridges omit it.
    public var updatedAt: Date?
    public var writable: Bool { workspaceID != nil && surfaceID != nil && state != "ended" }
    public init(id: String, agent: String, title: String, cwd: String?, workspaceID: String? = nil, surfaceID: String? = nil, state: String = "unknown", updatedAt: Date? = nil) {
        self.id = id; self.agent = agent; self.title = title; self.cwd = cwd; self.updatedAt = updatedAt
        self.workspaceID = workspaceID; self.surfaceID = surfaceID; self.state = state
    }
}
