import Foundation
import CmuxRemoteCore

/// A local view's exact remote producer binding; detachment never closes the producer.
public struct MirrorProjection: Codable, Sendable, Identifiable {
    public let id: UUID
    public let hostID: String
    public let workspaceID: String
    public let surfaceID: String
    public let runtimeEpoch: String
    public var localWorkspaceID: String?
    public var localSurfaceID: String?
    public init(id: UUID = UUID(), hostID: String, workspaceID: String, surfaceID: String, runtimeEpoch: String) {
        self.id = id; self.hostID = hostID; self.workspaceID = workspaceID; self.surfaceID = surfaceID; self.runtimeEpoch = runtimeEpoch
    }
}
