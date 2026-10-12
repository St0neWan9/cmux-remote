import Foundation

/// The exact local catalog workspace and pending terminal created by this Bridge.
public struct MirrorLocalSeed: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let surfaceID: String
    public let windowID: String
    public init(workspaceID: String, surfaceID: String, windowID: String) {
        self.workspaceID = workspaceID; self.surfaceID = surfaceID; self.windowID = windowID
    }
}
