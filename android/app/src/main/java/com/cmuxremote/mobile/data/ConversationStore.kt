package com.cmuxremote.mobile.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.array
import com.cmuxremote.mobile.protocol.asArray
import com.cmuxremote.mobile.protocol.asObject
import com.cmuxremote.mobile.protocol.bool
import com.cmuxremote.mobile.protocol.double
import com.cmuxremote.mobile.protocol.int
import com.cmuxremote.mobile.protocol.long
import com.cmuxremote.mobile.protocol.objectValue
import com.cmuxremote.mobile.protocol.string
import com.cmuxremote.mobile.protocol.strings
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.io.File
import java.time.Instant

/**
 * Conversations kept on the phone, in SQLite, so opening one shows every page already read.
 *
 * The Bridge serves a bounded window; this store keeps what the phone has been given,
 * keyed by the conversation's generation. A replacement generation wipes the
 * conversation instead of mixing two reads, and the store is never the authority:
 * a failed read or a corrupted file falls back to the network with a stable code.
 *
 * The schema mirrors the iPhone's `ConversationStore`: one metadata payload per
 * conversation, one message row per message, keyed by (scope, session id, id).
 */
class ConversationStore(context: Context, private val limits: Limits = Limits()) {
    /** What the phone is willing to spend on stored conversations. */
    data class Limits(
        val databaseBytes: Long = 536_870_912L,
        val conversationBytes: Long = 134_217_728L,
        val conversations: Int = 24,
        val messagesPerConversation: Int = 60_000,
    )

    private val lock = Any()
    private val helper = object : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
        override fun onCreate(db: SQLiteDatabase) = createSchema(db)

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // A cache is disposable: an old shape is dropped, never migrated in place.
            db.execSQL("DROP TABLE IF EXISTS meta")
            db.execSQL("DROP TABLE IF EXISTS message")
            db.execSQL("DROP TABLE IF EXISTS response")
            db.execSQL("DROP TABLE IF EXISTS image")
            createSchema(db)
        }
    }

    /** The whole stored conversation, or null when nothing usable is stored. */
    fun restore(scope: String, sessionID: String): ConversationSnapshot? = synchronized(lock) {
        runCatching {
            val db = helper.readableDatabase
            val meta = metadata(db, scope, sessionID) ?: return null
            val messages: List<ChatMessage> = rowsOf(db, scope, sessionID, TABLE_MESSAGE, "seq ASC") { parseMessage(it) }
            if (messages.isEmpty()) return null
            ConversationSnapshot(
                messages = messages,
                oldestSeq = messages.first().seq,
                generation = meta.generation,
                hasMore = meta.hasMore,
                clipped = meta.clipped,
                preview = null,
                images = rowsOf<ImageReference>(db, scope, sessionID, TABLE_IMAGE, "seq ASC") { parseImage(it) },
                backgroundTasks = meta.backgroundTasks,
                responses = rowsOf<ResponseTiming>(db, scope, sessionID, TABLE_RESPONSE, "seq ASC") { parseResponse(it) },
                recordedRunSeconds = meta.recordedRunSeconds,
                recordedTurnCount = meta.recordedTurnCount,
                currentTurnStartedAt = meta.currentTurnStartedAt,
                currentTurnCompleted = meta.currentTurnCompleted,
                agentModel = meta.agentModel,
            )
        }.getOrNull()
    }

    /** Whether the stored copy reaches the start of the transcript. */
    fun isComplete(scope: String, sessionID: String): Boolean = synchronized(lock) {
        runCatching { metadata(helper.readableDatabase, scope, sessionID)?.complete ?: false }.getOrDefault(false)
    }

    fun lastReadAt(scope: String, sessionID: String): Long? = synchronized(lock) {
        runCatching { metadata(helper.readableDatabase, scope, sessionID)?.readAt }.getOrNull()
    }

    /**
     * A page of stored messages older than [beforeSeq], shaped like the Bridge's page.
     * Null means this conversation's stored copy does not reach that far back.
     */
    fun page(scope: String, sessionID: String, beforeSeq: Int, limit: Int): ConversationSnapshot? = synchronized(lock) {
        runCatching {
            val db = helper.readableDatabase
            val meta = metadata(db, scope, sessionID) ?: return null
            val floor = scalar(db, "SELECT MIN(seq) FROM $TABLE_MESSAGE WHERE scope = ? AND session_id = ?", scope, sessionID)
                ?: return null
            if (beforeSeq <= floor) return null
            val messages = rowsOf<ChatMessage>(
                db, scope, sessionID, TABLE_MESSAGE, "seq DESC",
                where = "seq < ?", whereArgs = arrayOf(beforeSeq.toString()), limit = limit,
            ) { parseMessage(it) }
            if (messages.isEmpty()) return null
            ConversationSnapshot(
                messages = messages.reversed(),
                generation = meta.generation,
                hasMore = true,
                clipped = meta.clipped,
                preview = null,
            )
        }.getOrNull()
    }

    /** Writes one page. A new generation replaces the conversation; an older one is refused. */
    fun save(snapshot: ConversationSnapshot, scope: String, sessionID: String, complete: Boolean) {
        if (scope.isEmpty() || sessionID.isEmpty() || snapshot.messages.isEmpty()) return
        synchronized(lock) {
            runCatching {
                val db = helper.writableDatabase
                var stored = metadata(db, scope, sessionID)
                if (stored != null && stored.generation != snapshot.generation) {
                    deleteConversation(db, scope, sessionID)
                    stored = null
                }
                db.beginTransaction()
                try {
                    val record = stored ?: Meta(
                        generation = snapshot.generation,
                        clipped = snapshot.clipped,
                        hasMore = snapshot.hasMore,
                        complete = false,
                        recordedRunSeconds = null,
                        recordedTurnCount = 0,
                        currentTurnStartedAt = null,
                        currentTurnCompleted = false,
                        backgroundTasks = emptyList(),
                        agentModel = null,
                        readAt = System.currentTimeMillis(),
                    )
                    record.generation = snapshot.generation
                    record.hasMore = snapshot.hasMore
                    record.clipped = snapshot.clipped
                    record.complete = record.complete || complete || !snapshot.hasMore
                    snapshot.recordedRunSeconds?.let { record.recordedRunSeconds = it }
                    if (snapshot.recordedTurnCount > 0) record.recordedTurnCount = snapshot.recordedTurnCount
                    snapshot.currentTurnStartedAt?.let { record.currentTurnStartedAt = it }
                    record.currentTurnCompleted = snapshot.currentTurnCompleted
                    // Only a newest-page read reports tasks; an earlier page must not clear them.
                    if (snapshot.backgroundTasksPresent) record.backgroundTasks = snapshot.backgroundTasks
                    snapshot.agentModel?.let { record.agentModel = it }
                    record.readAt = System.currentTimeMillis()

                    upsert(db, TABLE_MESSAGE, scope, sessionID,
                        snapshot.messages.map { Triple(it.id, it.seq, encodeMessage(it)) })
                    upsert(db, TABLE_RESPONSE, scope, sessionID,
                        snapshot.responses.map { Triple(it.firstMessageID, 0, encodeResponse(it)) })
                    upsert(db, TABLE_IMAGE, scope, sessionID,
                        snapshot.images.map { Triple(it.id, 0, encodeImage(it)) })
                    setMetadata(db, scope, sessionID, record)
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
                trimConversation(db, scope, sessionID)
                trimDatabase(db)
            }
        }
    }

    fun remove(scope: String, sessionID: String) = synchronized(lock) {
        runCatching { deleteConversation(helper.writableDatabase, scope, sessionID) }
    }

    fun remove(scope: String) = synchronized(lock) {
        runCatching {
            val db = helper.writableDatabase
            for (table in TABLES) db.delete(table, "scope = ?", arrayOf(scope))
        }
    }

    /** Drops every stored conversation, for a deliberate identity reset. */
    fun clearAll() = synchronized(lock) {
        runCatching {
            val db = helper.writableDatabase
            for (table in TABLES) db.delete(table, null, null)
        }
    }

    private fun createSchema(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE_META (scope TEXT NOT NULL, session_id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id)) WITHOUT ROWID")
        db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE_MESSAGE (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
        db.execSQL("CREATE INDEX IF NOT EXISTS message_order ON $TABLE_MESSAGE (scope, session_id, seq)")
        db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE_RESPONSE (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
        db.execSQL("CREATE TABLE IF NOT EXISTS $TABLE_IMAGE (scope TEXT NOT NULL, session_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (scope, session_id, id)) WITHOUT ROWID")
    }

    // MARK: - Rows

    /** Decoded payloads of one table, in the caller's order. A row that cannot be read is skipped. */
    private fun <T> rowsOf(
        db: SQLiteDatabase,
        scope: String,
        sessionID: String,
        table: String,
        order: String,
        where: String? = null,
        whereArgs: Array<String> = emptyArray(),
        limit: Int? = null,
        parse: (JsonObject) -> T?,
    ): List<T> {
        val selection = buildString {
            append("scope = ? AND session_id = ?")
            if (where != null) append(" AND ").append(where)
        }
        val args = arrayOf(scope, sessionID) + whereArgs
        val values = mutableListOf<T>()
        db.query(
            table, arrayOf("payload"), selection, args, null, null, order,
            limit?.toString(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val payload = cursor.getBlob(0) ?: continue
                val parsed = runCatching {
                    Json.parse(String(payload, Charsets.UTF_8)) as? JsonObject
                }.getOrNull() ?: continue
                parse(parsed)?.let(values::add)
            }
        }
        return values
    }

    private fun upsert(db: SQLiteDatabase, table: String, scope: String, sessionID: String, rows: List<Triple<String, Int, String>>) {
        for ((id, seq, payload) in rows) {
            val values = ContentValues().apply {
                put("scope", scope)
                put("session_id", sessionID)
                put("id", id)
                put("seq", seq)
                put("payload", payload.toByteArray(Charsets.UTF_8))
            }
            db.insertWithOnConflict(table, null, values, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    private fun metadata(db: SQLiteDatabase, scope: String, sessionID: String): Meta? {
        val cursor = db.query(
            TABLE_META, arrayOf("payload"),
            "scope = ? AND session_id = ?", arrayOf(scope, sessionID),
            null, null, null, "1",
        )
        cursor.use {
            if (!it.moveToFirst()) return null
            val payload = it.getBlob(0) ?: return null
            val json = runCatching { Json.parse(String(payload, Charsets.UTF_8)) as? JsonObject }.getOrNull()
                ?: return null
            return parseMeta(json)
        }
    }

    private fun setMetadata(db: SQLiteDatabase, scope: String, sessionID: String, record: Meta) {
        val values = ContentValues().apply {
            put("scope", scope)
            put("session_id", sessionID)
            put("payload", encodeMeta(record).toByteArray(Charsets.UTF_8))
        }
        db.insertWithOnConflict(TABLE_META, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun deleteConversation(db: SQLiteDatabase, scope: String, sessionID: String) {
        for (table in TABLES) {
            db.delete(table, "scope = ? AND session_id = ?", arrayOf(scope, sessionID))
        }
    }

    private fun scalar(db: SQLiteDatabase, sql: String, vararg args: String): Int? {
        db.rawQuery(sql, args).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return cursor.getInt(0)
        }
    }

    private fun scalarLong(db: SQLiteDatabase, sql: String, vararg args: String): Long? {
        db.rawQuery(sql, args).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return cursor.getLong(0)
        }
    }

    /** Keeps a conversation bounded: the oldest rows go first, because the newest are what an opening shows. */
    private fun trimConversation(db: SQLiteDatabase, scope: String, sessionID: String) {
        val count = scalar(db, "SELECT COUNT(*) FROM $TABLE_MESSAGE WHERE scope = ? AND session_id = ?", scope, sessionID) ?: return
        if (count > limits.messagesPerConversation) {
            val excess = count - limits.messagesPerConversation
            db.execSQL(
                "DELETE FROM $TABLE_MESSAGE WHERE id IN (SELECT id FROM $TABLE_MESSAGE WHERE scope = ? AND session_id = ? ORDER BY seq ASC LIMIT ?)",
                arrayOf(scope, sessionID, excess),
            )
        }
        val total = scalarLong(db, "SELECT COALESCE(SUM(LENGTH(payload)), 0) FROM $TABLE_MESSAGE WHERE scope = ? AND session_id = ?", scope, sessionID) ?: return
        if (total > limits.conversationBytes) {
            db.execSQL(
                "DELETE FROM $TABLE_MESSAGE WHERE id IN (SELECT id FROM $TABLE_MESSAGE WHERE scope = ? AND session_id = ? ORDER BY seq ASC LIMIT ?)",
                arrayOf(scope, sessionID, maxOf(1, count / 4)),
            )
        }
    }

    /** Drops whole conversations, oldest read first, once the database is past its budget. */
    private fun trimDatabase(db: SQLiteDatabase) {
        val file = File(db.path)
        val conversations = runCatching {
            db.query(TABLE_META, arrayOf("scope", "session_id", "payload"), null, null, null, null, null)
                .use { cursor ->
                    val values = mutableListOf<Triple<String, String, Long>>()
                    while (cursor.moveToNext()) {
                        val scope = cursor.getString(0) ?: continue
                        val session = cursor.getString(1) ?: continue
                        val payload = cursor.getBlob(2) ?: continue
                        val json = runCatching { Json.parse(String(payload, Charsets.UTF_8)) as? JsonObject }.getOrNull()
                        values += Triple(scope, session, json?.long("readAt") ?: 0L)
                    }
                    values
                }
        }.getOrDefault(emptyList())
        val overBudget = file.exists() && file.length() > limits.databaseBytes
        if (conversations.size <= limits.conversations && !overBudget) return
        for ((scope, session, _) in conversations.sortedBy { it.third }.dropLast(limits.conversations)) {
            deleteConversation(db, scope, session)
        }
        // Reclaim the pages only when the file itself is over its bound.
        if (overBudget) runCatching { db.execSQL("VACUUM") }
    }

    // MARK: - Payloads

    private data class Meta(
        var generation: String,
        var clipped: Boolean,
        var hasMore: Boolean,
        var complete: Boolean,
        var recordedRunSeconds: Double?,
        var recordedTurnCount: Int,
        var currentTurnStartedAt: Instant?,
        var currentTurnCompleted: Boolean,
        var backgroundTasks: List<BackgroundTaskInfo>,
        var agentModel: String?,
        var readAt: Long,
    )

    private fun encodeMeta(meta: Meta): String = buildJsonObject {
        put("generation", JsonPrimitive(meta.generation))
        put("clipped", JsonPrimitive(meta.clipped))
        put("hasMore", JsonPrimitive(meta.hasMore))
        put("complete", JsonPrimitive(meta.complete))
        meta.recordedRunSeconds?.let { put("recordedRunSeconds", JsonPrimitive(it)) }
        put("recordedTurnCount", JsonPrimitive(meta.recordedTurnCount))
        meta.currentTurnStartedAt?.let { put("currentTurnStartedAt", JsonPrimitive(it.toString())) }
        put("currentTurnCompleted", JsonPrimitive(meta.currentTurnCompleted))
        put("backgroundTasks", JsonArray(meta.backgroundTasks.map { task ->
            buildJsonObject {
                put("id", JsonPrimitive(task.id))
                put("tool", JsonPrimitive(task.tool))
                put("summary", JsonPrimitive(task.summary))
                put("running", JsonPrimitive(task.running))
            }
        }))
        meta.agentModel?.let { put("agentModel", JsonPrimitive(it)) }
        put("readAt", JsonPrimitive(meta.readAt))
    }.toString()

    private fun parseMeta(json: JsonObject): Meta = Meta(
        generation = json.string("generation") ?: "",
        clipped = json.bool("clipped") ?: false,
        hasMore = json.bool("hasMore") ?: false,
        complete = json.bool("complete") ?: false,
        recordedRunSeconds = json.double("recordedRunSeconds"),
        recordedTurnCount = json.int("recordedTurnCount") ?: 0,
        currentTurnStartedAt = json.string("currentTurnStartedAt")?.let { runCatching { Instant.parse(it) }.getOrNull() },
        currentTurnCompleted = json.bool("currentTurnCompleted") ?: false,
        backgroundTasks = json.array("backgroundTasks")?.mapNotNull { row ->
            val task = row.asObject() ?: return@mapNotNull null
            BackgroundTaskInfo(
                id = task.string("id") ?: return@mapNotNull null,
                tool = task.string("tool") ?: "",
                summary = task.string("summary") ?: "",
                running = task.bool("running") ?: false,
            )
        } ?: emptyList(),
        agentModel = json.string("agentModel"),
        readAt = json.long("readAt") ?: 0L,
    )

    private fun encodeMessage(message: ChatMessage): String = buildJsonObject {
        put("id", JsonPrimitive(message.id))
        put("seq", JsonPrimitive(message.seq))
        put("role", JsonPrimitive(message.role))
        put("kind", JsonPrimitive(message.kind))
        put("text", JsonPrimitive(message.text))
        message.toolName?.let { put("tool_name", JsonPrimitive(it)) }
        message.status?.let { put("status", JsonPrimitive(it)) }
        message.filePath?.let { put("file_path", JsonPrimitive(it)) }
        message.diff?.let { put("diff", JsonPrimitive(it)) }
        message.prompt?.let { put("prompt", JsonPrimitive(it)) }
        if (message.options.isNotEmpty()) put("options", JsonArray(message.options.map { JsonPrimitive(it) }))
        message.selectedOption?.let { put("selected_option", JsonPrimitive(it)) }
        if (message.references.isNotEmpty()) put("references", JsonArray(message.references.map { JsonPrimitive(it) }))
        message.inputDetail?.let { put("input_detail", JsonPrimitive(it)) }
        message.output?.let { put("output", JsonPrimitive(it)) }
        message.command?.let { put("command", JsonPrimitive(it)) }
        message.exitCode?.let { put("exit_code", JsonPrimitive(it)) }
        message.durationSeconds?.let { put("duration_seconds", JsonPrimitive(it)) }
    }.toString()

    private fun parseMessage(json: JsonObject): ChatMessage? {
        val id = json.string("id") ?: return null
        return ChatMessage(
            id = id,
            seq = json.int("seq") ?: 0,
            role = json.string("role") ?: "agent",
            kind = json.string("kind") ?: "unsupported",
            text = json.string("text") ?: "",
            toolName = json.string("tool_name"),
            status = json.string("status"),
            filePath = json.string("file_path"),
            diff = json.string("diff"),
            prompt = json.string("prompt"),
            options = json.array("options")?.strings() ?: emptyList(),
            selectedOption = json.string("selected_option"),
            references = json.array("references")?.strings() ?: emptyList(),
            inputDetail = json.string("input_detail"),
            output = json.string("output"),
            command = json.string("command"),
            exitCode = json.int("exit_code"),
            durationSeconds = json.double("duration_seconds"),
        )
    }

    private fun encodeResponse(response: ResponseTiming): String = buildJsonObject {
        put("firstMessageID", JsonPrimitive(response.firstMessageID))
        put("lastMessageID", JsonPrimitive(response.lastMessageID))
        response.startedAt?.let { put("startedAt", JsonPrimitive(it.toString())) }
        response.completedAt?.let { put("completedAt", JsonPrimitive(it.toString())) }
        response.durationSeconds?.let { put("durationSeconds", JsonPrimitive(it)) }
        put("recordedDuration", JsonPrimitive(response.recordedDuration))
        put("completed", JsonPrimitive(response.completed))
        put("firstSeq", JsonPrimitive(response.firstSeq))
        put("lastSeq", JsonPrimitive(response.lastSeq))
    }.toString()

    private fun parseResponse(json: JsonObject): ResponseTiming? {
        val first = json.string("firstMessageID") ?: return null
        val last = json.string("lastMessageID") ?: return null
        return ResponseTiming(
            firstMessageID = first,
            lastMessageID = last,
            startedAt = json.string("startedAt")?.let { runCatching { Instant.parse(it) }.getOrNull() },
            completedAt = json.string("completedAt")?.let { runCatching { Instant.parse(it) }.getOrNull() },
            durationSeconds = json.double("durationSeconds"),
            recordedDuration = json.bool("recordedDuration") ?: false,
            completed = json.bool("completed") ?: false,
            firstSeq = json.int("firstSeq") ?: 0,
            lastSeq = json.int("lastSeq") ?: 0,
        )
    }

    private fun encodeImage(image: ImageReference): String = buildJsonObject {
        put("id", JsonPrimitive(image.id))
        put("messageID", JsonPrimitive(image.messageID))
        put("generation", JsonPrimitive(image.generation))
        put("name", JsonPrimitive(image.name))
    }.toString()

    private fun parseImage(json: JsonObject): ImageReference? {
        val id = json.string("id") ?: return null
        return ImageReference(
            id = id,
            messageID = json.string("messageID") ?: "",
            generation = json.string("generation") ?: "",
            name = json.string("name") ?: "",
        )
    }

    private companion object {
        const val DATABASE_NAME = "conversations.sqlite"
        const val DATABASE_VERSION = 1
        const val TABLE_META = "meta"
        const val TABLE_MESSAGE = "message"
        const val TABLE_RESPONSE = "response"
        const val TABLE_IMAGE = "image"
        val TABLES = listOf(TABLE_MESSAGE, TABLE_RESPONSE, TABLE_IMAGE, TABLE_META)
    }
}
