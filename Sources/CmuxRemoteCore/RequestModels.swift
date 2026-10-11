import Foundation

/// One logical mutation identity. A network failure is not an automatic retry signal.
public struct SendRequest: Codable, Sendable {
    public let text: String
    public let operationID: UUID
    public init(text: String, operationID: UUID = UUID()) { self.text = text; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case text; case operationID = "operation_id" }
}
public struct InterruptRequest: Codable, Sendable {
    public let hard: Bool
    public let operationID: UUID
    public init(hard: Bool = false, operationID: UUID = UUID()) { self.hard = hard; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case hard; case operationID = "operation_id" }
}
public struct MutationReceipt: Codable, Sendable {
    public let operationID: UUID
    public let accepted: Bool
    public init(operationID: UUID, accepted: Bool) { self.operationID = operationID; self.accepted = accepted }
}
public struct TextFileSnapshot: Codable, Sendable {
    public let path: String
    public let text: String
    public let truncated: Bool
    public init(path: String, text: String, truncated: Bool) { self.path = path; self.text = text; self.truncated = truncated }
}
