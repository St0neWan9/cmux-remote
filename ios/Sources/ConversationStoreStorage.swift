import Foundation
import SQLite3
import CmuxRemoteCore
import CmuxAgentChat

/// Values the store binds to a statement. Kept narrow on purpose: the store only ever binds text, integers and
/// blobs, and a narrower type removes every question about what a statement received.
/// SQLite copies a binding whose destructor is TRANSIENT, which is what a string or data that outlives the call needs.
let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol SQLiteValue: Sendable {}
extension String: SQLiteValue {}
extension Int: SQLiteValue {}
extension Data: SQLiteValue {}

extension SQLiteValue {
    func bind(to statement: OpaquePointer, at index: Int32) {
        switch self {
        case let value as String: sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
        case let value as Data: sqlite3_bind_blob(statement, index, [UInt8](value), Int32(value.count), sqliteTransient)
        default: sqlite3_bind_null(statement, index)
        }
    }

}

extension ConversationStore {
    func value(_ database: OpaquePointer, _ sql: String, _ bindings: [any SQLiteValue] = [], column: Int32 = 0) -> String? {
        guard let statement = prepare(database, sql, bindings) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }
    func scalar(_ database: OpaquePointer, _ sql: String, _ bindings: [any SQLiteValue] = []) -> Int? {
        guard let statement = prepare(database, sql, bindings) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
    func metadata(_ database: OpaquePointer, scope: String, sessionID: String) -> StoredConversationRecord? {
        guard let statement = prepare(database, "SELECT payload FROM meta WHERE scope = ? AND session_id = ?", [scope, sessionID]) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: bytes, count: count)
        return try? JSONDecoder().decode(StoredConversationRecord.self, from: data)
    }
    func setMetadata(_ database: OpaquePointer, scope: String, sessionID: String, _ record: StoredConversationRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        execute(database, "INSERT OR REPLACE INTO meta (scope, session_id, payload) VALUES (?, ?, ?)", [scope, sessionID, data])
    }
    /// Decoded rows of a table, ordered by the statement's own `order`.
    func rows<T: Decodable>(_ database: OpaquePointer, scope: String, sessionID: String, table: String, whereSQL: String? = nil, bind: [any SQLiteValue] = [], order: String, as type: T.Type) -> [T]? {
        let filter = whereSQL.map { " AND \($0)" } ?? ""
        guard let statement = prepare(database, "SELECT payload FROM \(table) WHERE scope = ? AND session_id = ?\(filter) ORDER BY \(order)", [scope, sessionID] + bind) else { return nil }
        defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            if let value = try? JSONDecoder().decode(T.self, from: data) { values.append(value) }
        }
        return values
    }
    func messageRows(_ database: OpaquePointer, scope: String, sessionID: String, whereSQL: String, bind: [any SQLiteValue], order: String, limit: Int) -> [ChatMessage] {
        guard let statement = prepare(database, "SELECT payload FROM message WHERE scope = ? AND session_id = ? AND \(whereSQL) ORDER BY \(order) LIMIT ?", [scope, sessionID] + bind + [limit]) else { return [] }
        defer { sqlite3_finalize(statement) }
        var values: [ChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            if let value = try? JSONDecoder().decode(ChatMessage.self, from: data) { values.append(value) }
        }
        return values
    }
    /// Writes rows in one prepared statement. A message a tool result updated in place replaces the stored copy.
    func upsert<T: Encodable>(_ database: OpaquePointer, scope: String, sessionID: String, table: String, rows: [(id: String, seq: Int, payload: T)]) {
        guard !rows.isEmpty, let statement = prepare(database, "INSERT OR REPLACE INTO \(table) (scope, session_id, id, seq, payload) VALUES (?, ?, ?, ?, ?)", [scope, sessionID, "", 0, Data()]) else { return }
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        for row in rows {
            guard let data = try? encoder.encode(row.payload) else { continue }
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, scope, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, sessionID, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, row.id, -1, sqliteTransient)
            sqlite3_bind_int64(statement, 4, Int64(row.seq))
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(data.count), sqliteTransient) }
            sqlite3_step(statement)
        }
    }
    func delete(_ database: OpaquePointer, scope: String, sessionID: String) {
        execute(database, "DELETE FROM message WHERE scope = ? AND session_id = ?", [scope, sessionID])
        execute(database, "DELETE FROM response WHERE scope = ? AND session_id = ?", [scope, sessionID])
        execute(database, "DELETE FROM image WHERE scope = ? AND session_id = ?", [scope, sessionID])
        execute(database, "DELETE FROM meta WHERE scope = ? AND session_id = ?", [scope, sessionID])
    }
    /// Keeps a conversation bounded: the oldest rows go first, because the newest are what an opening shows.
    func trim(_ database: OpaquePointer, scope: String, sessionID: String) {
        guard let count = scalar(database, "SELECT COUNT(*) FROM message WHERE scope = ? AND session_id = ?", [scope, sessionID]),
              count > limits.messagesPerConversation else { return }
        let excess = count - limits.messagesPerConversation
        execute(database, "DELETE FROM message WHERE id IN (SELECT id FROM message WHERE scope = ? AND session_id = ? ORDER BY seq ASC LIMIT ?)", [scope, sessionID, excess])
        guard let total = scalar(database, "SELECT COALESCE(SUM(LENGTH(payload)), 0) FROM message WHERE scope = ? AND session_id = ?", [scope, sessionID]),
              total > limits.conversationBytes else { return }
        execute(database, "DELETE FROM message WHERE id IN (SELECT id FROM message WHERE scope = ? AND session_id = ? ORDER BY seq ASC LIMIT ?)", [scope, sessionID, max(1, count / 4)])
    }
    /// Drops whole conversations, oldest read first, once the database is past its budget.
    func trimDatabase() {
        guard let database = open() else { return }
        defer { sqlite3_close(database) }
        let budget = limits.databaseBytes
        guard let pages = scalar(database, "PRAGMA page_count"), let size = scalar(database, "PRAGMA page_size"), pages * size > budget else { return }
        guard let statement = prepare(database, "SELECT scope, session_id FROM meta ORDER BY json_extract(payload, '$.readAt') ASC", []) else { return }
        var victims: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let scope = sqlite3_column_text(statement, 0), let session = sqlite3_column_text(statement, 1) else { continue }
            victims.append((String(cString: scope), String(cString: session)))
        }
        sqlite3_finalize(statement)
        for victim in victims.dropLast(limits.conversations) { delete(database, scope: victim.0, sessionID: victim.1) }
        execute(database, "VACUUM")
    }
}

/// The conversation-level record kept beside its messages.
struct StoredConversationRecord: Codable, Sendable {
    var generation: String
    var clipped: Bool
    var hasMore: Bool
    var complete: Bool
    var recordedRunSeconds: Double?
    var recordedTurnCount: Int?
    var currentTurnStartedAt: Date?
    var currentTurnCompleted: Bool?
    var backgroundTasks: [BackgroundAgentTask]?
    var agentModel: AgentModelState?
    var readAt: Date
}
