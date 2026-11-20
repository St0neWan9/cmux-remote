import Foundation

/// A project root the Bridge found inside one approved workspace. The phone selects it by `id`, never by path.
public struct LaunchDirectory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// For display only, with the home directory shown as `~`.
    public let path: String
    public init(id: String, path: String) { self.id = id; self.path = path }
}
