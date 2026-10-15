import Foundation

/// cmux confirmed the new terminal. The agent's conversation appears separately once the agent reports it.
public struct StartSessionReceipt: Codable, Sendable, Equatable {
    public let operationID: UUID
    public let accepted: Bool
    /// The new terminal; absent when an earlier receipt is replayed.
    public let surfaceID: String?
    public init(operationID: UUID, accepted: Bool, surfaceID: String?) { self.operationID = operationID; self.accepted = accepted; self.surfaceID = surfaceID }
    private enum CodingKeys: String, CodingKey { case accepted; case operationID = "operation_id"; case surfaceID = "surface_id" }
}
