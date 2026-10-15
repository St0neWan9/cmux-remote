import Foundation

/// Starts one agent in a new terminal. A network failure is not an automatic retry signal.
public struct StartSessionRequest: Codable, Sendable, Equatable {
    public let rootID: String
    /// Relative to the root; empty for the root itself.
    public let path: String
    public let agent: LaunchAgent
    public let operationID: UUID
    public init(rootID: String, path: String = "", agent: LaunchAgent, operationID: UUID = UUID()) {
        self.rootID = rootID; self.path = path; self.agent = agent; self.operationID = operationID
    }
    private enum CodingKeys: String, CodingKey { case path, agent; case rootID = "root_id"; case operationID = "operation_id" }
}
