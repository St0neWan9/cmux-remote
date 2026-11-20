import Foundation

/// A cmux response confirmed by the Bridge; not proof that the model processed the input.
public struct MutationReceipt: Codable, Sendable {
    public let operationID: UUID
    public let accepted: Bool
    public init(operationID: UUID, accepted: Bool) { self.operationID = operationID; self.accepted = accepted }
}
