import Foundation

/// One model switch with a stable logical identity. A network failure is not an automatic retry signal.
public struct ModelSwitchRequest: Codable, Sendable {
    /// A choice the Bridge offered or a name the reader typed; the Bridge validates it before any input.
    public let model: String
    public let operationID: UUID
    /// Answers "yes" when the agent asks to confirm the switch; without it the agent's question is declined and reported.
    public let confirm: Bool
    public init(model: String, operationID: UUID = UUID(), confirm: Bool = false) { self.model = model; self.operationID = operationID; self.confirm = confirm }
    private enum CodingKeys: String, CodingKey { case model, confirm; case operationID = "operation_id" }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        operationID = try values.decode(UUID.self, forKey: .operationID)
        confirm = try values.decodeIfPresent(Bool.self, forKey: .confirm) ?? false
    }
}
