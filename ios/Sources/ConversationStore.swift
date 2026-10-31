import Foundation
import SQLite3
import CmuxRemoteCore
import CmuxAgentChat

/// A conversation kept on the phone, so reading back through it never asks the Mac again.
///
/// The Bridge serves a bounded window and the phone used to keep only the newest page, which is why scrolling
/// back over a long conversation always went to the network. This store keeps every page it is given, keyed by
/// the conversation's generation: a replacement generation wipes the conversation instead of mixing two reads.
///
/// It is a cache, never the authority. A failure here falls back to the network with a stable code, and a
/// corrupted file is dropped rather than repaired.
actor ConversationStore {
    /// What the phone is willing to spend on stored conversations.
    struct Limits: Sendable {
        var databaseBytes = 536_870_912
        var conversationBytes = 134_217_728
        var conversations = 24
        var messagesPerConversation = 60_000
    }
    private let directory: URL
    let limits: Limits
    private var handle: OpaquePointer?
    init(directory: URL? = nil, limits: Limits = Limits()) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Conversations", isDirectory: true)
        self.limits = limits
    }

    /// The whole stored conversation, or nil when nothing usable is stored for this generation.
    func restore(scope: String, sessionID: String) -> ConversationSnapshot? {
        guard let database = open() else { return nil }
        defer { sqlite3_close(database) }
        guard let stored = metadata(database, scope: scope, sessionID: sessionID) else { return nil }
        guard let messages = rows(database, scope: scope, sessionID: sessionID, table: "message", order: "seq ASC", as: ChatMessage.self),
              !messages.isEmpty else { return nil }
        return ConversationSnapshot(messages: messages, hasMore: stored.hasMore, generation: stored.generation, clipped: stored.clipped,
                                    responses: rows(database, scope: scope, sessionID: sessionID, table: "response", order: "seq ASC", as: ConversationResponse.self),
                                    recordedRunSeconds: stored.recordedRunSeconds, recordedTurnCount: stored.recordedTurnCount,
                                    currentTurnStartedAt: stored.currentTurnStartedAt, currentTurnCompleted: stored.currentTurnCompleted,
                                    images: rows(database, scope: scope, sessionID: sessionID, table: "image", order: "seq ASC", as: ConversationImageReference.self),
                                    backgroundTasks: stored.backgroundTasks, agentModel: stored.agentModel)
    }
    /// Whether the stored copy reaches the start of the transcript.
    func isComplete(scope: String, sessionID: String) -> Bool {
        guard let database = open() else { return false }
        defer { sqlite3_close(database) }
        return metadata(database, scope: scope, sessionID: sessionID)?.complete ?? false
    }
    func earliestSeq(scope: String, sessionID: String) -> Int? {
        guard let database = open() else { return nil }
        defer { sqlite3_close(database) }
        return scalar(database, "SELECT MIN(seq) FROM message WHERE scope = ? AND session_id = ?", [scope, sessionID])
    }
    func lastReadAt(scope: String, sessionID: String) -> Date? {
        guard let database = open() else { return nil }
        defer { sqlite3_close(database) }
        return metadata(database, scope: scope, sessionID: sessionID)?.readAt
    }
    /// A page of stored messages older than `beforeSeq`, shaped like the Bridge's own page.
    func page(scope: String, sessionID: String, beforeSeq: Int, limit: Int) -> ConversationSnapshot? {
        guard let database = open() else { return nil }
        defer { sqlite3_close(database) }
        guard let stored = metadata(database, scope: scope, sessionID: sessionID) else { return nil }
        guard let floor = scalar(database, "SELECT MIN(seq) FROM message WHERE scope = ? AND session_id = ?", [scope, sessionID]), beforeSeq > floor else { return nil }
        let rows = messageRows(database, scope: scope, sessionID: sessionID, whereSQL: "seq < ?", bind: [beforeSeq], order: "seq DESC", limit: limit)
        guard !rows.isEmpty else { return nil }
        return ConversationSnapshot(messages: rows.reversed(), hasMore: true, generation: stored.generation, clipped: stored.clipped)
    }

    /// Writes one page. A new generation replaces the conversation; an older generation is refused.
    func save(_ snapshot: ConversationSnapshot, scope: String, sessionID: String, complete: Bool) {
        guard let database = open() else { return }
        defer { sqlite3_close(database) }
        var stored = metadata(database, scope: scope, sessionID: sessionID)
        if let current = stored, current.generation != snapshot.generation { stored = nil; delete(database, scope: scope, sessionID: sessionID) }
        execute(database, "BEGIN IMMEDIATE")
        var record = stored ?? StoredConversationRecord(generation: snapshot.generation, clipped: snapshot.clipped, hasMore: snapshot.hasMore, complete: false,
                                                  readAt: Date())
        record.generation = snapshot.generation
        record.hasMore = snapshot.hasMore
        record.clipped = snapshot.clipped
        record.complete = record.complete || complete || !snapshot.hasMore
        record.recordedRunSeconds = snapshot.recordedRunSeconds ?? record.recordedRunSeconds
        record.recordedTurnCount = snapshot.recordedTurnCount ?? record.recordedTurnCount
        record.currentTurnStartedAt = snapshot.currentTurnStartedAt ?? record.currentTurnStartedAt
        record.currentTurnCompleted = snapshot.currentTurnCompleted ?? record.currentTurnCompleted
        record.backgroundTasks = snapshot.backgroundTasks ?? record.backgroundTasks
        record.agentModel = snapshot.agentModel ?? record.agentModel
        record.readAt = Date()
        upsert(database, scope: scope, sessionID: sessionID, table: "message", rows: snapshot.messages.map { ($0.id, $0.seq, $0) })
        upsert(database, scope: scope, sessionID: sessionID, table: "response", rows: (snapshot.responses ?? []).map { ($0.firstMessageID, $0.firstSeq, $0) })
        upsert(database, scope: scope, sessionID: sessionID, table: "image", rows: (snapshot.images ?? []).map { ($0.id, 0, $0) })
        setMetadata(database, scope: scope, sessionID: sessionID, record)
        execute(database, "COMMIT")
        trim(database, scope: scope, sessionID: sessionID)
    }
    func remove(scope: String, sessionID: String) {
        guard let database = open() else { return }
        defer { sqlite3_close(database) }
        delete(database, scope: scope, sessionID: sessionID)
    }
    func remove(scope: String) {
        guard let database = open() else { return }
        defer { sqlite3_close(database) }
        execute(database, "DELETE FROM message WHERE scope = ?", [scope])
        execute(database, "DELETE FROM response WHERE scope = ?", [scope])
        execute(database, "DELETE FROM image WHERE scope = ?", [scope])
        execute(database, "DELETE FROM meta WHERE scope = ?", [scope])
    }
    // MARK: - Files and schema

    private func file() -> URL { directory.appendingPathComponent("conversations.sqlite") }
    func open() -> OpaquePointer? {
        if let handle { return handle }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var value: OpaquePointer?
        let url = file()
        guard sqlite3_open_v2(url.path, &value, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let value else {
            sqlite3_close(value); try? FileManager.default.removeItem(at: url); return nil
        }
        handle = value
        execute(value, "PRAGMA journal_mode = WAL")
        execute(value, "PRAGMA synchronous = NORMAL")
        // Tables are created on every open: an older or corrupt file then fails loudly at the first statement
        // rather than silently serving a conversation under the wrong shape.
        execute(value, "CREATE TABLE IF NOT EXISTS meta (scope TEXT NOT NULL, session_id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id)) WITHOUT ROWID")
        execute(value, "CREATE TABLE IF NOT EXISTS message (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
        execute(value, "CREATE INDEX IF NOT EXISTS message_order ON message (scope, session_id, seq)")
        execute(value, "CREATE TABLE IF NOT EXISTS response (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
        execute(value, "CREATE TABLE IF NOT EXISTS image (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
        return value
    }
    func execute(_ database: OpaquePointer, _ sql: String, _ bindings: [any SQLiteValue] = []) {
        guard let statement = prepare(database, sql, bindings) else { return }
        sqlite3_step(statement); sqlite3_finalize(statement)
    }
    func prepare(_ database: OpaquePointer, _ sql: String, _ bindings: [any SQLiteValue]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        for (index, value) in bindings.enumerated() { value.bind(to: statement, at: Int32(index + 1)) }
        return statement
    }
}
