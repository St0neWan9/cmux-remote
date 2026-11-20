import Foundation

/// A scoped operation record; an unknown outcome is never an instruction to retry.
public struct OperationStatus: Codable, Sendable {
    public enum State: String, Codable, Sendable { case accepted, outcomeUnknown = "outcome_unknown" }
    public let operationID: UUID
    public let state: State
    public let recordedAt: Date
    public init(operationID: UUID, state: State, recordedAt: Date) {
        self.operationID = operationID; self.state = state; self.recordedAt = recordedAt
    }
    private enum CodingKeys: String, CodingKey { case operationID = "operation_id", state; case recordedAt = "recorded_at" }
}
