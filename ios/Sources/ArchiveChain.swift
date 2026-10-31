import Foundation
import CmuxRemoteCore

/// Reads a conversation from the Bridge's archive route, newest page first and then downward.
///
/// The windowed history route stops at the Bridge's own 32 MB window, so a long conversation could never be read
/// in full. The archive route pages the whole transcript with a cursor, and this actor owns that cursor: one
/// chain per open conversation, so the pages always move in one direction and never mix two seq spaces.
///
/// The newest read and the reader's place are two different things. A tail refresh asks for what just arrived
/// with no cursor; taking its answer's cursor as the chain's would drag the reader back to the newest page every
/// few seconds, and every pull-down would then hand back messages already on screen. Only a chain that has not
/// started, or one whose transcript was replaced, takes its place from that read.
actor ArchiveChain {
    private let read: @Sendable (String?, Int) async throws -> ConversationArchivePage
    /// Below the earliest page handed out; nil once the transcript's start has been reached.
    private var cursor: String?
    /// The transcript the cursor belongs to. A replaced transcript reuses no byte offset.
    private var generation: String?
    private var started = false
    init(read: @escaping @Sendable (String?, Int) async throws -> ConversationArchivePage) { self.read = read }

    /// The newest page. The first call starts the chain; later calls show new messages without moving the place
    /// the reader paged to.
    ///
    /// The page's own cursor comes back with it: a burst that produced more than one page since the last read
    /// leaves a hole below it, and that hole is read from this cursor without touching the reader's place.
    func newest(limit: Int) async throws -> (page: ConversationSnapshot, cursor: String?, hasMore: Bool) {
        let page = try await read(nil, limit)
        if !started || generation != page.snapshot.generation {
            started = true
            generation = page.snapshot.generation
            cursor = page.nextCursor
        }
        return (page.snapshot, page.nextCursor, cursor != nil)
    }
    /// One page ending at a cursor this chain handed out, leaving the reader's own place untouched.
    func page(from cursor: String, limit: Int) async throws -> ConversationArchivePage {
        let page = try await read(cursor, limit)
        if generation != page.snapshot.generation {
            started = false; self.cursor = nil; generation = nil
            throw BridgeError("history_cursor_stale", "This archive cursor belongs to a different conversation record. Reload the archive.", status: 409)
        }
        return page
    }
    /// The next older page, or nil once the start of the transcript is stored.
    func older(limit: Int) async throws -> (page: ConversationSnapshot, hasMore: Bool)? {
        guard started, let cursor else { return nil }
        let page: ConversationArchivePage
        do { page = try await read(cursor, limit) }
        catch let error as BridgeError where error.code == "history_cursor_stale" {
            // The transcript was replaced under the reader; the next newest read repositions the chain.
            started = false; self.cursor = nil; generation = nil
            throw error
        }
        generation = page.snapshot.generation
        self.cursor = page.nextCursor
        return (page.snapshot, page.nextCursor != nil)
    }
    /// Whether the chain still has pages below the one it last returned.
    var hasMore: Bool { cursor != nil }
}
