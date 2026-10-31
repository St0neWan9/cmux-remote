import Foundation
import CmuxRemoteCore

/// Reads a conversation from the Bridge's archive route, newest page first and then downward.
///
/// The windowed history route stops at the Bridge's own 32 MB window, so a long conversation could never be read
/// in full. The archive route pages the whole transcript with a cursor, and this actor owns that cursor: one
/// chain per open conversation, so the pages always move in one direction and never mix two seq spaces.
///
/// A Bridge without the route answers 404; the caller then keeps the windowed route for that conversation.
actor ArchiveChain {
    private let read: @Sendable (String?, Int) async throws -> ConversationArchivePage
    /// Below the earliest page handed out; nil once the transcript's start has been reached.
    private var cursor: String?
    private var started = false
    init(read: @escaping @Sendable (String?, Int) async throws -> ConversationArchivePage) { self.read = read }

    /// The newest page. The first call starts the chain; later calls continue from where it is, so a tail refresh
    /// never rewinds the reader's position.
    func newest(limit: Int) async throws -> (page: ConversationSnapshot, hasMore: Bool) {
        if started {
            let page = try await read(nil, limit)
            cursor = page.nextCursor
            return (page.snapshot, page.nextCursor != nil)
        }
        started = true
        let page = try await read(nil, limit)
        cursor = page.nextCursor
        return (page.snapshot, page.nextCursor != nil)
    }
    /// The next older page, or nil once the start of the transcript is stored.
    func older(limit: Int) async throws -> (page: ConversationSnapshot, hasMore: Bool)? {
        guard let cursor else { return nil }
        let page = try await read(cursor, limit)
        self.cursor = page.nextCursor
        return (page.snapshot, page.nextCursor != nil)
    }
    /// Whether the chain still has pages below the one it last returned.
    var hasMore: Bool { cursor != nil }
}
