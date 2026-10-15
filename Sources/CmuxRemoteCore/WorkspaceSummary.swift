import Foundation

/// Public workspace metadata returned by the already scoped workspace listing.
public struct WorkspaceSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
    public init?(json: JSONValue) {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        self.id = id; title = json["title"].string ?? json["name"].string ?? id
    }
}
