import Foundation

/// One terminal's stable IDs; commands, environment and local paths are never exported.
public struct MirrorSurface: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let paneID: String
    public let title: String
    public init(id: String, paneID: String, title: String) { self.id = id; self.paneID = paneID; self.title = title }
}
