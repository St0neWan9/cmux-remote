import Foundation

/// A selected image keeps its identity through draft edits and one logical send.
public struct ChatImagePayload: Codable, Sendable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let format: String
    public let dataBase64: String
    public init(id: UUID = UUID(), fileName: String, format: String, data: Data) {
        self.id = id; self.fileName = fileName; self.format = format; dataBase64 = data.base64EncodedString()
    }
    private enum CodingKeys: String, CodingKey { case id, format; case fileName = "file_name", dataBase64 = "data_b64" }
}
