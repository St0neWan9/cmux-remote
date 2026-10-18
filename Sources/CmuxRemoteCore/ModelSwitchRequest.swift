import Foundation

/// One model switch with a stable logical identity. A network failure is not an automatic retry signal.
public struct ModelSwitchRequest: Codable, Sendable {
    /// A choice the Bridge offered or a name the reader typed; the Bridge validates it before any input.
    public let model: String
    public let operationID: UUID
    public init(model: String, operationID: UUID = UUID()) { self.model = model; self.operationID = operationID }
    private enum CodingKeys: String, CodingKey { case model; case operationID = "operation_id" }
}
