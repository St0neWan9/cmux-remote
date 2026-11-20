import Foundation

/// Reports local structural synchronization without exposing remote credentials.
public struct MirrorSyncStatus: Codable, Sendable {
    public let hostID: String
    public let workspaceID: String
    public let localWorkspaceID: String
    public let state: String
    public let errorCode: String?
    public let detail: String?
}
