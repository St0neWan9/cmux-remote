import Foundation

/// Option identity is independent of its display label; distinct choices may have equal labels.
public struct FeedQuestionOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let detail: String?
    public init(id: String, label: String, detail: String? = nil) { self.id = id; self.label = label; self.detail = detail }
    public init(json: JSONValue, fallbackIndex: Int) {
        id = json["id"].string.flatMap { $0.isEmpty ? nil : $0 } ?? String(fallbackIndex)
        label = json["label"].string ?? ""; detail = json["description"].string
    }
}
