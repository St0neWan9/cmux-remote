import Foundation

/// One page of the complete conversation archive, with a cursor for older messages.
///
/// The snapshot's generation is stable for a transcript path across Bridge restarts as long as
/// the record is neither replaced nor truncated. `complete` means this page reaches the first
/// record, so no older cursor exists.
public struct ConversationArchivePage: Codable, Sendable {
    public let snapshot: ConversationSnapshot
    public let nextCursor: String?
    public let complete: Bool
    public init(snapshot: ConversationSnapshot, nextCursor: String?, complete: Bool) {
        self.snapshot = snapshot; self.nextCursor = nextCursor; self.complete = complete
    }
}
