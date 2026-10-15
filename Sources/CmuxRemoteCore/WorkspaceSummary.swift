import Foundation

/// Public workspace metadata returned by the already scoped workspace listing.
public struct WorkspaceSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Desktop cmux workspaces can open new terminals; daemon (cmux-tui) workspaces cannot.
    public let startsSessions: Bool
    public init(id: String, title: String, startsSessions: Bool = true) { self.id = id; self.title = title; self.startsSessions = startsSessions }
    public init?(json: JSONValue) {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        self.id = id; title = json["title"].string ?? json["name"].string ?? id
        startsSessions = json["backend"].string != "cmux-tui"
    }
}
