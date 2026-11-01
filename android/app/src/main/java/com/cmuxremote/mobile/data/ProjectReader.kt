package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.array
import com.cmuxremote.mobile.protocol.asObject
import com.cmuxremote.mobile.protocol.asString
import com.cmuxremote.mobile.protocol.bool
import com.cmuxremote.mobile.protocol.string
import kotlinx.serialization.json.JsonElement
import java.net.URLEncoder

/** Reads a conversation's project through the Bridge's fixed, path-scoped routes. */
class ProjectReader(
    private val call: suspend (method: String, path: String, query: Map<String, String>, body: ByteArray?) -> JsonElement,
) {
    suspend fun changes(sessionID: String): List<ProjectChange> {
        val value = call("GET", "/v2/sessions/${segment(sessionID)}/changes", emptyMap(), null)
        val object_ = value.asObject() ?: throw ProtocolException("invalid_response", "The change list is not an object.")
        return parseChanges(object_.array("entries")?.mapNotNull { it.asString() } ?: emptyList())
    }

    suspend fun diff(sessionID: String, path: String): ProjectText = text(sessionID, "diff", path)

    suspend fun file(sessionID: String, path: String): ProjectText = text(sessionID, "file", path)

    private suspend fun text(sessionID: String, resource: String, path: String): ProjectText {
        val value = call("GET", "/v2/sessions/${segment(sessionID)}/$resource", mapOf("path" to path), null)
        val object_ = value.asObject() ?: throw ProtocolException("invalid_response", "The project text is not an object.")
        return ProjectText(
            path = object_.string("path") ?: path,
            text = object_.string("text") ?: "",
            truncated = object_.bool("truncated") ?: false,
        )
    }

    companion object {
        private const val STATUS_CHARACTERS = " MADRCU?!"

        private fun segment(id: String): String = URLEncoder.encode(id, "UTF-8").replace("+", "%20")

        /**
         * Splits NUL-delimited porcelain v1 rows. A rename or copy is followed by its source
         * path as the next entry, which this model drops.
         */
        private fun parseChanges(entries: List<String>): List<ProjectChange> {
            val result = mutableListOf<ProjectChange>()
            var index = 0
            while (index < entries.size) {
                val row = entries[index]
                index += 1
                if (row.length < 4 || row[2] != ' ') continue
                val status = row.substring(0, 2)
                if (!status.all { STATUS_CHARACTERS.contains(it) }) continue
                val path = row.substring(3)
                if (path.isEmpty()) continue
                if (status.contains('R') || status.contains('C')) {
                    if (index < entries.size) index += 1
                }
                result += ProjectChange(path = path, status = status, added = null, removed = null)
            }
            return result
        }
    }
}

data class ProjectChange(val path: String, val status: String, val added: Int?, val removed: Int?)
data class ProjectText(val path: String, val text: String, val truncated: Boolean)
