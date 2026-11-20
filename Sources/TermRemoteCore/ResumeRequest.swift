import Foundation

/// Reopening one conversation in a new terminal. The caller names only the conversation: the Agent session and the
/// directory come from the Bridge's own binding and the Agent's transcript, so no host path or command crosses the wire.
public struct ResumeRequest: Codable, Sendable {
    public let operationID: UUID
    public init(operationID: UUID = UUID()) { self.operationID = operationID }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try container.decodeIfPresent(UUID.self, forKey: .operationID) ?? UUID()
    }
    private enum CodingKeys: String, CodingKey { case operationID = "operation_id" }
}
