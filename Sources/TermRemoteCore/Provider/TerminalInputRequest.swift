import Foundation

/// One logical terminal input. The operation id makes a retry safe to detect;
/// it does not make the provider atomic.
public struct TerminalInputRequest: Codable, Sendable, Equatable {
    public let text: String
    public let submit: Bool?
    public let operationID: UUID

    public init(text: String, submit: Bool? = nil, operationID: UUID) {
        self.text = text; self.submit = submit; self.operationID = operationID
    }
    private enum CodingKeys: String, CodingKey { case text, submit; case operationID = "operation_id" }
}
