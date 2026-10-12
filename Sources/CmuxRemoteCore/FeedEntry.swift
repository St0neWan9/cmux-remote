import Foundation

/// Stable request identity prevents another pending card from inheriting an earlier question's draft.
public struct FeedEntry: Sendable, Identifiable {
    public let id: String
    public let value: JSONValue
    public init(value: JSONValue, fallbackIndex: Int) {
        self.value = value
        if let id = value["id"].string { self.id = "item:" + id }
        else if let id = value["request_id"].string { self.id = "request:" + id }
        else { self.id = "event:" + String(fallbackIndex) }
    }
}
