import Foundation

/// Input bound to the runtime observed by the viewer, with a stable mutation identity.
public struct MirrorInputRequest: Codable, Sendable {
    public let runtimeEpoch: String
    public let text: String
    public let operationID: UUID
    public init(runtimeEpoch: String, text: String, operationID: UUID = UUID()) {
        self.runtimeEpoch = runtimeEpoch; self.text = text; self.operationID = operationID
    }
}
