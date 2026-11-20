import Foundation

/// One rename with a stable logical identity; an empty title clears the custom name so cmux shows its own again.
public struct SessionRenameRequest: Codable, Sendable {
    public let title: String
    public let operationID: UUID
    public init(title: String, operationID: UUID = UUID()) { self.title = title; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case title; case operationID = "operation_id" }
}
