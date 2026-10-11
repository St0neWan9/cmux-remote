import Foundation

/// One logical send identity. A network failure is not an automatic retry signal.
public struct SendRequest: Codable, Sendable {
    public let text: String
    public let operationID: UUID
    public init(text: String, operationID: UUID = UUID()) { self.text = text; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case text; case operationID = "operation_id" }
}
