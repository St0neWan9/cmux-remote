package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.asObject
import com.cmuxremote.mobile.protocol.bool
import com.cmuxremote.mobile.protocol.int
import com.cmuxremote.mobile.protocol.long
import com.cmuxremote.mobile.protocol.string
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption

/**
 * The last read of one background task, kept on the phone so reopening its page
 * shows content at once. Mirrors the iPhone's `BackgroundTaskCache`: the stored
 * copy is shown first, and the read that follows either confirms or replaces it.
 *
 * A task is identified by scope, session and task id; those three are hashed into
 * the file name, so nothing from the Bridge can escape the cache directory. The
 * cache is bounded to 16 entries and 4 MiB per entry; an oversized copy is simply
 * not saved. Reading is a use, so a copy survives the next eviction pass.
 */
class BackgroundTaskCache(private val directory: File) {
    /** One task's stored page: enough to render the sheet before the Mac answers. */
    data class Entry(
        val tool: String,
        val summary: String,
        val running: Boolean,
        val text: String,
        val nextOffset: Int?,
        val storedAt: Long,
    )

    private val lock = Any()

    fun load(scope: String, sessionID: String, taskID: String): Entry? {
        synchronized(lock) {
            val source = file(scope, sessionID, taskID)
            return runCatching {
                if (!isRegularFile(source) || source.length() > ENTRY_LIMIT) return null
                val text = source.readText()
                if (text.toByteArray(Charsets.UTF_8).size > ENTRY_LIMIT) return null
                val json = Json.parse(text) as? JsonObject ?: return null
                val entry = parse(json) ?: return null
                // Reading it is a use, so the copy survives the next eviction pass.
                source.setLastModified(System.currentTimeMillis())
                entry
            }.getOrNull()
        }
    }

    fun save(entry: Entry, scope: String, sessionID: String, taskID: String) {
        synchronized(lock) {
            if (scope.isEmpty() || sessionID.isEmpty() || taskID.isEmpty()) return
            val bytes = encode(entry).toByteArray(Charsets.UTF_8)
            if (bytes.size > ENTRY_LIMIT) return
            runCatching {
                ensureDirectory()
                val target = file(scope, sessionID, taskID)
                val temporary = File(directory, target.name + ".tmp")
                try {
                    temporary.writeBytes(bytes)
                    ownerOnly(temporary)
                    moveIntoPlace(temporary, target)
                    ownerOnly(target)
                } catch (error: Exception) {
                    temporary.delete()
                    throw error
                }
                prune(keep = target)
            }
        }
    }

    /** Removes every stored task of one host + device scope. */
    fun remove(scope: String) = synchronized(lock) {
        val prefix = Identity.digest(scope.toByteArray(Charsets.UTF_8)) + "."
        runCatching {
            directory.listFiles()?.forEach { entry ->
                if (entry.isFile && entry.name.startsWith(prefix)) entry.delete()
            }
        }
    }

    /** How many tasks currently have a stored copy. */
    fun entryCount(): Int = synchronized(lock) { entries().size }

    /** Drops every stored task record, for a deliberate identity reset. */
    fun clearAll() = synchronized(lock) {
        runCatching { directory.listFiles()?.forEach { it.delete() } }
    }

    private fun encode(entry: Entry): String = buildJsonObject {
        put("tool", JsonPrimitive(entry.tool))
        put("summary", JsonPrimitive(entry.summary))
        put("running", JsonPrimitive(entry.running))
        put("text", JsonPrimitive(entry.text))
        entry.nextOffset?.let { put("nextOffset", JsonPrimitive(it)) }
        put("storedAt", JsonPrimitive(entry.storedAt))
    }.toString()

    private fun parse(json: JsonObject): Entry? {
        val text = json.string("text") ?: return null
        return Entry(
            tool = json.string("tool") ?: "",
            summary = json.string("summary") ?: "",
            running = json.bool("running") ?: false,
            text = text,
            nextOffset = json.int("nextOffset"),
            storedAt = json.long("storedAt") ?: 0L,
        )
    }

    /** All three identities are hashed, so a name can never leave the directory. */
    private fun file(scope: String, sessionID: String, taskID: String): File =
        File(
            directory,
            Identity.digest(scope.toByteArray(Charsets.UTF_8)) + "." +
                Identity.digest((sessionID + "\u0000" + taskID).toByteArray(Charsets.UTF_8)) + ".json",
        )

    private fun entries(): List<File> =
        directory.listFiles()?.filter { it.isFile && it.name.endsWith(".json") } ?: emptyList()

    private fun ensureDirectory() {
        if (!directory.isDirectory) directory.mkdirs()
        ownerOnlyDirectory(directory)
    }

    private fun moveIntoPlace(temp: File, target: File) {
        try {
            Files.move(
                temp.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    /** Least recently used copies go first; the copy just saved is always kept. */
    private fun prune(keep: File) {
        val sorted = entries().sortedBy { it.lastModified() }
        var excess = sorted.size - ENTRY_COUNT
        if (excess <= 0) return
        for (entry in sorted) {
            if (excess <= 0) return
            if (entry == keep) continue
            if (entry.delete()) excess--
        }
    }

    private fun isRegularFile(file: File): Boolean =
        runCatching { Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS) }.getOrDefault(false)

    private fun ownerOnly(file: File) {
        file.setReadable(false, false)
        file.setWritable(false, false)
        file.setExecutable(false, false)
        file.setReadable(true, true)
        file.setWritable(true, true)
    }

    private fun ownerOnlyDirectory(path: File) {
        path.setReadable(false, false)
        path.setWritable(false, false)
        path.setExecutable(false, false)
        path.setReadable(true, true)
        path.setWritable(true, true)
        path.setExecutable(true, true)
    }

    private companion object {
        const val ENTRY_LIMIT = 4_194_304
        const val ENTRY_COUNT = 16
    }
}
