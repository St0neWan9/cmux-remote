import Foundation

/// One logical send identity. A network failure is not an automatic retry signal.
public struct SendRequest: Codable, Sendable {
    public let text: String
    public let operationID: UUID
    public let attachments: [ChatImagePayload]
    public init(text: String, operationID: UUID = UUID(), attachments: [ChatImagePayload] = []) { self.text = text; self.operationID = operationID; self.attachments = attachments }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text); operationID = try container.decode(UUID.self, forKey: .operationID)
        attachments = try container.decodeIfPresent([ChatImagePayload].self, forKey: .attachments) ?? []
    }
    private enum CodingKeys: String, CodingKey { case text, attachments; case operationID = "operation_id" }
}
