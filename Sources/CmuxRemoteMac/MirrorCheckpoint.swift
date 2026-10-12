import Foundation
import CmuxRemoteCore

/// Durable metadata only; credentials and terminal content never enter this record.
public struct MirrorCheckpoint: Codable, Sendable {
    public let host: HostIdentity
    public let localWorkspaceID: String
    public let snapshot: MirrorWorkspaceSnapshot
    public let projections: [MirrorProjection]
    public init(host: HostIdentity, localWorkspaceID: String, snapshot: MirrorWorkspaceSnapshot, projections: [MirrorProjection]) {
        self.host = host; self.localWorkspaceID = localWorkspaceID; self.snapshot = snapshot; self.projections = projections
    }
}
