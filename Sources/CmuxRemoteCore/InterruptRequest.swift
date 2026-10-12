import Foundation

/// A stop action with one stable logical identity.
public struct InterruptRequest: Codable, Sendable {
    public let hard: Bool
    public let operationID: UUID
    public init(hard: Bool = false, operationID: UUID = UUID()) { self.hard = hard; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case hard; case operationID = "operation_id" }
}
