import Foundation

/// A scoped remote workspace and its terminal-only layout projection.
public struct MirrorWorkspaceSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let layout: JSONValue
    public let surfaces: [MirrorSurface]
    public init(id: String, title: String, layout: JSONValue, surfaces: [MirrorSurface]) {
        self.id = id; self.title = title; self.layout = layout; self.surfaces = surfaces
    }
}
