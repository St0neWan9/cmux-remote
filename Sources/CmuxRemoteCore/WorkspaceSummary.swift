import Foundation

/// Public workspace metadata returned by the already scoped workspace listing.
public struct WorkspaceSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Set for a provider space such as a Rex session; nil for a cmux workspace.
    public let providerID: String?
    public init(id: String, title: String, providerID: String? = nil) { self.id = id; self.title = title; self.providerID = providerID }
    public init?(json: JSONValue) {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        self.id = id; title = json["title"].string ?? json["name"].string ?? id
        providerID = json["provider_id"].string
    }
}
