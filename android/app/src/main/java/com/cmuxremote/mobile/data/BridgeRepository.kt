package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.bridge.BridgeClient
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.bool
import com.cmuxremote.mobile.protocol.double
import com.cmuxremote.mobile.protocol.asObject
import com.cmuxremote.mobile.protocol.array
import com.cmuxremote.mobile.protocol.asArray
import com.cmuxremote.mobile.protocol.int
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.jsonString
import com.cmuxremote.mobile.protocol.objectValue
import com.cmuxremote.mobile.protocol.string
import com.cmuxremote.mobile.protocol.strings
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.util.UUID

/** One conversation the Bridge reports for this device's workspaces. */
data class SessionDescriptor(
    val id: String,
    val agent: String,
    val title: String,
    val cwd: String?,
    val workspaceID: String?,
    val surfaceID: String?,
    val state: String,
    val updatedAt: String?,
    val resumable: Boolean,
) {
    val writable: Boolean get() = workspaceID != null && surfaceID != null && state != "ended"
    val working: Boolean get() = state.startsWith("working")
}

/** What one timeline row renders; unknown payloads keep their text rather than vanishing. */
data class ChatMessage(
    val id: String,
    val seq: Int,
    val role: String,
    val kind: String,
    val text: String,
    val toolName: String? = null,
    val status: String? = null,
    val filePath: String? = null,
    val diff: String? = null,
    val prompt: String? = null,
    val options: List<String> = emptyList(),
    val selectedOption: String? = null,
    /** Project-relative paths the tool input named. */
    val references: List<String> = emptyList(),
    /** A tool's full input, its result, or a terminal command's own fields. */
    val inputDetail: String? = null,
    val output: String? = null,
    val command: String? = null,
    val exitCode: Int? = null,
    val durationSeconds: Double? = null,
)

/** Timing anchors for one prompt and its response, as the Bridge recorded them. */
data class ResponseTiming(
    val firstMessageID: String,
    val lastMessageID: String,
    val startedAt: java.time.Instant?,
    val completedAt: java.time.Instant?,
    val durationSeconds: Double?,
    val recordedDuration: Boolean,
    val completed: Boolean,
    /** Transcript positions, so pages read earlier can be put before newer ones. */
    val firstSeq: Int = 0,
    val lastSeq: Int = 0,
)

/** A history page; the generation names the transcript revision it was read from. */
data class ConversationSnapshot(
    val messages: List<ChatMessage>,
    val oldestSeq: Int? = messages.firstOrNull()?.seq,
    val generation: String,
    val hasMore: Boolean,
    val clipped: Boolean,
    val preview: String?,
    val images: List<ImageReference> = emptyList(),
    val backgroundTasks: List<BackgroundTaskInfo> = emptyList(),
    /** Only a newest-page read reports tasks; an earlier page must not clear them. */
    val backgroundTasksPresent: Boolean = false,
    val responses: List<ResponseTiming> = emptyList(),
    /** Total recorded running time and the turns that contributed it. */
    val recordedRunSeconds: Double? = null,
    val recordedTurnCount: Int = 0,
    /** When the unfinished turn began, so the page can count from the real start. */
    val currentTurnStartedAt: java.time.Instant? = null,
    val currentTurnCompleted: Boolean = false,
    /** The model the transcript last reported, as the agent itself named it. */
    val agentModel: String? = null,
)

/** One page of a complete tool record. */
data class ToolDetailPage(
    val text: String,
    val nextOffset: Int?,
    val contentID: String?,
    val generation: String,
    val totalCharacters: Int,
)

/** One task the agent detached; its own record is read on demand. */
data class BackgroundTaskInfo(val id: String, val tool: String, val summary: String, val running: Boolean)

/** One page of a detached task's record; a null next offset means the record ended. */
data class TaskPage(val text: String, val nextOffset: Int?)

/** An opaque image reference bound to one recorded message and transcript generation. */
data class ImageReference(val id: String, val messageID: String, val generation: String, val name: String)

/** A captured Feed item waiting for, or recording, a decision. */
data class FeedItem(
    val requestID: String,
    val kind: String,
    val status: String,
    val title: String,
    val questions: List<FeedQuestion>,
    val plan: String? = null,
    val body: String? = null,
    val toolName: String? = null,
    val toolInput: String? = null,
    val toolResult: String? = null,
    val toolResultIsError: Boolean = false,
    val feedback: String? = null,
    val decisionMode: String? = null,
    val selections: List<String> = emptyList(),
)

data class FeedQuestion(val prompt: String, val options: List<String>, val multiSelect: Boolean)

/** The Bridge writes ISO-8601 dates; a malformed one is no timing at all. */
private fun instantOrNull(text: String): java.time.Instant? =
    runCatching { java.time.Instant.parse(text) }.getOrNull()

/** Authorized reads and writes against one paired Bridge. */
class BridgeRepository(val connection: AuthorizedConnection, private val client: BridgeClient) {
    /** Runs one read with `link` installed, restoring the previous transport after. */
    suspend fun <T> withLink(link: com.cmuxremote.mobile.bridge.LinkClient, block: suspend BridgeRepository.() -> T): T {
        val previous = relayLink
        useRelayLink(link)
        try {
            return block()
        } finally {
            if (previous == null) {
                relayLink = null
                client.clearLink()
            }
        }
    }

    /** Routes reads through the relay link once the LAN path is proven unreachable. */
    fun useRelayLink(client: com.cmuxremote.mobile.bridge.LinkClient) {
        this.relayLink = client
        this.client.useLink(client)
    }

    val overRelay: Boolean get() = relayLink != null

    var relayLink: com.cmuxremote.mobile.bridge.LinkClient? = null
        private set

    /** The epoch the next signed read would use; the link binds its subscriptions to it. */
    suspend fun epoch(): String = client.currentEpoch()

    /**
     * One real round trip to the Bridge, for the connection page's reachability
     * check. The epoch may be cached; this never is.
     */
    suspend fun probe() {
        client.announcement()
    }

    suspend fun workspaces(): List<Pair<String, String>> {
        val value = client.call("GET", "/v2/workspaces")
        val list = value.asObject()?.array("workspaces") ?: return emptyList()
        return list.mapNotNull { row ->
            val object_ = row.asObject() ?: return@mapNotNull null
            val id = object_.string("id") ?: return@mapNotNull null
            id to (object_.string("title") ?: "Workspace")
        }
    }

    suspend fun sessions(): List<SessionDescriptor> {
        val value = client.call("GET", "/v2/sessions")
        return value.asArray()?.mapNotNull { row -> row.asObject()?.let(::decodeSession) } ?: emptyList()
    }

    suspend fun history(sessionID: String, beforeSeq: Int? = null, limit: Int = 100): ConversationSnapshot {
        val query = buildMap {
            if (beforeSeq != null) put("before_seq", beforeSeq.toString())
            put("limit", limit.toString())
        }
        val value = client.call("GET", "/v2/sessions/$sessionID/history", query)
        val object_ = value.asObject() ?: throw ProtocolException("invalid_response", "The history page is not an object.")
        val messages = object_.array("messages")?.mapNotNull(::decodeMessage) ?: emptyList()
        return ConversationSnapshot(
            messages = messages,
            oldestSeq = messages.minOfOrNull { it.seq },
            generation = object_.string("generation") ?: "",
            hasMore = object_.bool("hasMore") ?: false,
            clipped = object_.bool("clipped") ?: false,
            preview = null,
            responses = object_.array("responses")?.mapNotNull { row ->
                val response = row.asObject() ?: return@mapNotNull null
                val first = response.string("firstMessageID") ?: return@mapNotNull null
                val last = response.string("lastMessageID") ?: return@mapNotNull null
                ResponseTiming(
                    firstMessageID = first,
                    lastMessageID = last,
                    startedAt = response.string("startedAt")?.let(::instantOrNull),
                    completedAt = response.string("completedAt")?.let(::instantOrNull),
                    durationSeconds = response.double("durationSeconds"),
                    recordedDuration = response.bool("recordedDuration") ?: false,
                    completed = response.bool("completed") ?: false,
                    firstSeq = response.int("firstSeq") ?: 0,
                    lastSeq = response.int("lastSeq") ?: 0,
                )
            } ?: emptyList(),
            recordedRunSeconds = object_.double("recordedRunSeconds"),
            recordedTurnCount = object_.int("recordedTurnCount") ?: 0,
            currentTurnStartedAt = object_.string("currentTurnStartedAt")?.let(::instantOrNull),
            currentTurnCompleted = object_.bool("currentTurnCompleted") ?: false,
            agentModel = object_.objectValue("agentModel")?.string("model"),
            images = object_.array("images")?.mapNotNull { row ->
                val image = row.asObject() ?: return@mapNotNull null
                ImageReference(
                    id = image.string("id") ?: return@mapNotNull null,
                    messageID = image.string("messageID") ?: return@mapNotNull null,
                    generation = image.string("generation") ?: return@mapNotNull null,
                    name = image.string("name") ?: "",
                )
            } ?: emptyList(),
            backgroundTasksPresent = object_.array("backgroundTasks") != null,
            backgroundTasks = object_.array("backgroundTasks")?.mapNotNull { row ->
                val task = row.asObject() ?: return@mapNotNull null
                BackgroundTaskInfo(
                    id = task.string("id") ?: return@mapNotNull null,
                    tool = task.string("tool") ?: "",
                    summary = task.string("summary") ?: "",
                    running = true,
                )
            } ?: emptyList(),
        )
    }

    suspend fun preview(sessionID: String): String? {
        val value = client.call("GET", "/v2/sessions/$sessionID/preview")
        return value.asObject()?.string("text")?.takeIf { it.isNotBlank() }
    }

    /** Sends one prompt. The operation id is the durable identity; a failure is never auto-retried. */
    suspend fun send(sessionID: String, text: String, operationID: String = UUID.randomUUID().toString()): JsonElement {
        val body = buildJsonObject {
            put("text", JsonPrimitive(text))
            put("operation_id", JsonPrimitive(operationID))
            put("attachments", kotlinx.serialization.json.JsonArray(emptyList()))
        }
        return client.call("POST", "/v2/sessions/$sessionID/send", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    suspend fun interrupt(sessionID: String, hard: Boolean = false): JsonElement {
        val body = buildJsonObject {
            put("hard", JsonPrimitive(hard))
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
        }
        return client.call("POST", "/v2/sessions/$sessionID/interrupt", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    suspend fun feed(): List<FeedItem> {
        val value = client.call("GET", "/v2/feed")
        return value.asObject()?.array("items")?.mapNotNull { row ->
            val object_ = row.asObject() ?: return@mapNotNull null
            FeedItem(
                requestID = object_.string("request_id") ?: object_.string("id") ?: return@mapNotNull null,
                kind = object_.string("kind") ?: "",
                status = object_.string("status") ?: "",
                title = object_.string("title") ?: object_.string("tool_name") ?: "",
                plan = object_.string("plan"),
                body = object_.string("body"),
                toolName = object_.string("tool_name"),
                toolInput = object_.string("tool_input"),
                toolResult = object_.string("tool_result"),
                toolResultIsError = object_.bool("tool_result_is_error") ?: false,
                feedback = object_.objectValue("decision")?.string("feedback"),
                decisionMode = object_.objectValue("decision")?.string("mode"),
                selections = object_.objectValue("decision")?.array("selections")?.strings() ?: emptyList(),
                questions = object_.array("questions")?.mapNotNull { question ->
                    val q = question.asObject() ?: return@mapNotNull null
                    FeedQuestion(
                        prompt = q.string("prompt") ?: "",
                        options = q.array("options")?.mapNotNull { option ->
                            (option.asObject()?.string("label"))
                        } ?: emptyList(),
                        multiSelect = q.bool("multi_select") ?: false,
                    )
                } ?: emptyList(),
            )
        } ?: emptyList()
    }

    /** Answers a permission or plan request with one fixed decision mode. */
    suspend fun reply(requestID: String, kind: String, mode: String, feedback: String? = null): JsonElement {
        val body = buildJsonObject {
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
            put("kind", JsonPrimitive(kind))
            put("mode", JsonPrimitive(mode))
            if (feedback != null) put("feedback", JsonPrimitive(feedback))
        }
        return client.call("POST", "/v2/feed/$requestID/reply", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    /** Answers a question request with one label per question. */
    suspend fun answer(requestID: String, kind: String, selections: List<String>): JsonElement {
        val body = buildJsonObject {
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
            put("kind", JsonPrimitive(kind))
            put("selections", kotlinx.serialization.json.JsonArray(selections.map { JsonPrimitive(it) }))
        }
        return client.call("POST", "/v2/feed/$requestID/reply", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    suspend fun operation(operationID: String): JsonObject {
        val value = client.call("GET", "/v2/operations/$operationID")
        return value.asObject() ?: JsonObject(emptyMap())
    }

    /** A recorded image preview, bounded by the Bridge to a 512 KiB JPEG. */
    suspend fun image(sessionID: String, reference: ImageReference): ByteArray =
        client.bytes(
            "/v2/sessions/$sessionID/image",
            mapOf("reference_id" to reference.id, "generation" to reference.generation),
            limit = 524_288,
        )

    /** Sends a prompt with prepared attachments. */
    suspend fun sendWithImages(
        sessionID: String,
        text: String,
        images: List<Pair<String, String>>,
        operationID: String = UUID.randomUUID().toString(),
    ): JsonElement {
        val body = buildJsonObject {
            put("text", JsonPrimitive(text))
            put("operation_id", JsonPrimitive(operationID))
            put("attachments", kotlinx.serialization.json.JsonArray(images.map { (fileName, data) ->
                buildJsonObject {
                    put("id", JsonPrimitive(UUID.randomUUID().toString()))
                    put("file_name", JsonPrimitive(fileName))
                    put("format", JsonPrimitive("jpeg"))
                    put("data_b64", JsonPrimitive(data))
                }
            }))
        }
        return client.call("POST", "/v2/sessions/$sessionID/send", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    /** One page of a complete tool record, read from the committed transcript. */
    suspend fun toolDetail(
        sessionID: String,
        messageID: String,
        field: String,
        generation: String,
        offset: Int = 0,
        contentID: String? = null,
    ): ToolDetailPage {
        val query = buildMap {
            put("message_id", messageID)
            put("field", field)
            put("generation", generation)
            put("offset", offset.toString())
            if (contentID != null) put("content_id", contentID)
        }
        val value = client.call("GET", "/v2/sessions/$sessionID/tool-detail", query)
        val object_ = value.asObject() ?: throw ProtocolException("invalid_response", "The tool record is not an object.")
        return ToolDetailPage(
            text = object_.string("text") ?: "",
            nextOffset = object_.int("next_offset"),
            contentID = object_.string("content_id"),
            generation = object_.string("generation") ?: generation,
            totalCharacters = object_.int("total_characters") ?: 0,
        )
    }

    /** One page of a detached task's own record. */
    suspend fun task(sessionID: String, taskID: String, offset: Int = 0): TaskPage {
        val value = client.call("GET", "/v2/sessions/$sessionID/tasks/$taskID", mapOf("offset" to offset.toString()))
        val object_ = value.asObject() ?: return TaskPage("", null)
        val text = object_.string("text") ?: object_.string("output") ?: ""
        return TaskPage(text, object_.int("next_offset"))
    }

    /** Folders a workspace can start a conversation in. */
    suspend fun startRoots(workspaceID: String): List<Pair<String, String>> {
        val value = client.call("GET", "/v2/workspaces/$workspaceID/directories")
        // The Bridge answers the folder list itself; an older shape wrapped it in `roots`.
        val rows = value.asArray() ?: value.asObject()?.array("roots") ?: return emptyList()
        return rows.mapNotNull { row ->
            val root = row.asObject() ?: return@mapNotNull null
            val id = root.string("id") ?: return@mapNotNull null
            id to (root.string("path") ?: id)
        }
    }

    /** Opens a terminal running a fixed agent command in an approved folder. */
    suspend fun startSession(workspaceID: String, rootID: String, path: String, agent: String, prompt: String?): JsonElement {
        val body = buildJsonObject {
            put("root_id", JsonPrimitive(rootID))
            put("path", JsonPrimitive(path))
            put("agent", JsonPrimitive(agent))
            if (!prompt.isNullOrBlank()) put("prompt", JsonPrimitive(prompt))
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
        }
        return client.call("POST", "/v2/workspaces/$workspaceID/sessions", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    /** The conversation's project, read through the Bridge's path-scoped routes. */
    suspend fun project(): ProjectReader = ProjectReader { method, path, query, body -> client.call(method, path, query, body) }

    suspend fun models(sessionID: String): List<Pair<String, String>> {
        val value = client.call("GET", "/v2/sessions/$sessionID/models")
        return value.asObject()?.array("choices")?.mapNotNull { row ->
            val choice = row.asObject() ?: return@mapNotNull null
            val id = choice.string("id") ?: return@mapNotNull null
            id to (choice.string("label") ?: id)
        } ?: emptyList()
    }

    suspend fun switchModel(sessionID: String, model: String, confirm: Boolean = false): JsonElement {
        val body = buildJsonObject {
            put("model", JsonPrimitive(model))
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
            put("confirm", JsonPrimitive(confirm))
        }
        return client.call("POST", "/v2/sessions/$sessionID/model", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    suspend fun rename(sessionID: String, title: String): JsonElement {
        val body = buildJsonObject {
            put("title", JsonPrimitive(title))
            put("operation_id", JsonPrimitive(UUID.randomUUID().toString()))
        }
        return client.call("POST", "/v2/sessions/$sessionID/title", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    /** Reopens an ended Agent session in a new terminal of its own workspace. */
    suspend fun resume(sessionID: String): JsonElement {
        val body = buildJsonObject { put("operation_id", JsonPrimitive(UUID.randomUUID().toString())) }
        return client.call("POST", "/v2/sessions/$sessionID/resume", emptyMap(), com.cmuxremote.mobile.protocol.Json.bytes(body))
    }

    companion object {
        fun open(connection: AuthorizedConnection): BridgeRepository {
            val http = com.cmuxremote.mobile.bridge.PinnedHttpClient(
                connection.endpoint.host,
                connection.endpoint.port,
                connection.host.certificateSHA256,
            )
            val client = BridgeClient(http, connection.host, connection.privateKey, connection.clientID)
            return BridgeRepository(connection, client)
        }

        private fun decodeSession(object_: JsonObject): SessionDescriptor? {
            val id = object_.string("id") ?: return null
            return SessionDescriptor(
                id = id,
                agent = object_.string("agent") ?: "claude",
                title = object_.string("title") ?: "Untitled",
                cwd = object_.string("cwd"),
                workspaceID = object_.string("workspaceID"),
                surfaceID = object_.string("surfaceID"),
                state = object_.string("state") ?: "unknown",
                updatedAt = object_.string("updatedAt"),
                resumable = object_.bool("resumable") ?: false,
            )
        }

        /** Reads the session list background sync stored, for a first frame before the live read. */
        fun decodeSessions(json: String): List<SessionDescriptor> = runCatching {
            (Json.parse(json) as? kotlinx.serialization.json.JsonArray)
                ?.mapNotNull { row -> row.asObject()?.let(::decodeSession) }
                ?: emptyList()
        }.getOrDefault(emptyList())

        /** The same shape background sync writes, so a failed live read can fall back to it. */
        fun encodeSessions(sessions: List<SessionDescriptor>): String = Json.text(
            kotlinx.serialization.json.JsonArray(
                sessions.map { session ->
                    buildJsonObject {
                        put("id", JsonPrimitive(session.id))
                        put("agent", JsonPrimitive(session.agent))
                        put("title", JsonPrimitive(session.title))
                        session.cwd?.let { put("cwd", JsonPrimitive(it)) }
                        session.workspaceID?.let { put("workspaceID", JsonPrimitive(it)) }
                        session.surfaceID?.let { put("surfaceID", JsonPrimitive(it)) }
                        put("state", JsonPrimitive(session.state))
                        session.updatedAt?.let { put("updatedAt", JsonPrimitive(it)) }
                        put("resumable", JsonPrimitive(session.resumable))
                    }
                },
            ),
        )

        /** Decodes one transcript message leniently: an unknown kind still shows its text. */
        fun decodeMessage(row: JsonElement): ChatMessage? {
            val object_ = row.asObject() ?: return null
            val id = object_.string("id") ?: return null
            val seq = object_.int("seq") ?: 0
            val role = object_.string("role") ?: "agent"
            val kind = object_.objectValue("kind") ?: JsonObject(emptyMap())
            val type = kind.string("type") ?: "unsupported"
            val prompt = kind.string("prompt")
            val options = kind.array("options")?.mapNotNull { option ->
                (option.asObject()?.string("label")) ?: (option as? JsonPrimitive)?.content
            } ?: emptyList()
            return ChatMessage(
                id = id,
                seq = seq,
                role = role,
                kind = type,
                text = kind.string("text") ?: kind.string("summary") ?: kind.string("prompt") ?: "",
                toolName = kind.string("tool_name") ?: kind.string("toolName"),
                status = kind.string("status"),
                filePath = kind.string("file_path") ?: kind.string("filePath"),
                diff = kind.string("unified_diff") ?: kind.string("unifiedDiff") ?: kind.string("diff"),
                prompt = prompt,
                options = options.map { it.toString().trim('"') },
                selectedOption = kind.string("selected_option_label"),
                references = kind.array("referenced_paths")?.strings()
                    ?: kind.array("referencedPaths")?.strings()
                    ?: emptyList(),
                inputDetail = kind.string("input_detail") ?: kind.string("inputDetail"),
                output = kind.string("output"),
                command = kind.string("command"),
                exitCode = kind.int("exit_code") ?: kind.int("exitCode"),
                durationSeconds = kind.double("duration_seconds") ?: kind.double("durationSeconds"),
            )
        }
    }
}
