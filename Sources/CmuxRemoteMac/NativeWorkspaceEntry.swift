import Foundation

/// Protected local mapping for an authorized remote inventory row.
public struct NativeWorkspaceEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let hostID: String
    public let workspaceID: String
    public var title: String
    public var state: String
    public var seed: MirrorLocalSeed?
    public var projectionID: UUID?
    public var errorCode: String?
    public init(id: UUID = UUID(), hostID: String, workspaceID: String, title: String, state: String = "creating") {
        self.id = id; self.hostID = hostID; self.workspaceID = workspaceID; self.title = title; self.state = state
    }
}
