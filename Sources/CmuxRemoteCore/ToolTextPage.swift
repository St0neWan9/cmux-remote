import Foundation

/// One bounded page of a transcript-derived tool field, bound to its content revision.
public struct ToolTextPage: Codable, Sendable {
    public let messageID: String
    public let generation: String
    public let field: String
    public let contentID: String
    public let text: String
    public let offset: Int
    public let nextOffset: Int?
    public let totalCharacters: Int
    public init(messageID: String, generation: String, field: String, contentID: String, text: String, offset: Int, nextOffset: Int?, totalCharacters: Int) {
        self.messageID = messageID; self.generation = generation; self.field = field; self.contentID = contentID
        self.text = text; self.offset = offset; self.nextOffset = nextOffset; self.totalCharacters = totalCharacters
    }
    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id", generation, field, contentID = "content_id", text, offset, nextOffset = "next_offset", totalCharacters = "total_characters"
    }
}
