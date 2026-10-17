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
    /// Whether the Agent session can be reopened in a new terminal: its workspace outlived the terminal and its own
    /// transcript still names the directory. Only a Bridge that verified both says so.
    public var resumable: Bool
    public var writable: Bool { workspaceID != nil && surfaceID != nil && state != "ended" }
    public init(id: String, agent: String, title: String, cwd: String?, workspaceID: String? = nil, surfaceID: String? = nil, state: String = "unknown", updatedAt: Date? = nil, resumable: Bool = false) {
        self.id = id; self.agent = agent; self.title = title; self.cwd = cwd; self.updatedAt = updatedAt
        self.workspaceID = workspaceID; self.surfaceID = surfaceID; self.state = state; self.resumable = resumable
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); agent = try c.decode(String.self, forKey: .agent)
        title = try c.decode(String.self, forKey: .title); cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID); surfaceID = try c.decodeIfPresent(String.self, forKey: .surfaceID)
        state = try c.decode(String.self, forKey: .state); updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        resumable = try c.decodeIfPresent(Bool.self, forKey: .resumable) ?? false
    }
}
