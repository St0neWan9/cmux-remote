import Foundation

/// A project-level container: a cmux workspace, a Rex session, or another
/// provider's equivalent. It is the unit of navigation, sharing and grants.
public struct SpaceDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let providerID: String
    public let title: String
    /// A provider-neutral hint for the UI, such as "workspace" or "session".
    public let kind: String?

    public init(id: String, providerID: String, title: String, kind: String? = nil) {
        self.id = id; self.providerID = providerID; self.title = title; self.kind = kind
    }
}
