package com.cmuxremote.mobile.background

import android.content.Context
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
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
 * The newest session list and pending count per Mac, written by background sync and read on launch.
 *
 * The cache is a convenience, never authority: every entry is replaced by a fresh signed
 * read. It is bounded to eight Macs and 512 KiB per payload, and each file is owner-only
 * inside the app's private data directory.
 */
class SessionSnapshotCache(context: Context) {
    private val directory = File(context.filesDir, "background")
    private val lock = Any()

    /** Writes one Mac's newest read, replacing any earlier copy. Oversized payloads are dropped. */
    fun save(hostID: String, sessionsJson: String, pendingCount: Int, at: Long) {
        if (hostID.isEmpty()) return
        if (sessionsJson.toByteArray(Charsets.UTF_8).size > MAX_PAYLOAD_BYTES) return
        val text = Json.text(
            buildJsonObject {
                put("sessionsJson", JsonPrimitive(sessionsJson))
                put("pendingCount", JsonPrimitive(pendingCount.coerceAtLeast(0)))
                put("at", JsonPrimitive(at))
            },
        )
        synchronized(lock) {
            runCatching {
                ensureDirectory()
                val target = file(hostID)
                val temp = File(directory, target.name + ".tmp")
                try {
                    temp.writeText(text)
                    ownerOnly(temp)
                    moveIntoPlace(temp, target)
                    ownerOnly(target)
                } catch (error: Exception) {
                    temp.delete()
                    throw error
                }
                prune(keep = target)
            }
        }
    }

    /** The last copy for one Mac, or null when absent, malformed, or over its bound. */
    fun load(hostID: String): Snapshot? = synchronized(lock) {
        if (hostID.isEmpty()) return@synchronized null
        val source = file(hostID)
        if (!isRegularFile(source) || source.length() > MAX_FILE_BYTES) return@synchronized null
        val parsed = runCatching { Json.parse(source.readText()) as? JsonObject }.getOrNull()
            ?: return@synchronized null
        val sessions = parsed.string("sessionsJson") ?: return@synchronized null
        if (sessions.toByteArray(Charsets.UTF_8).size > MAX_PAYLOAD_BYTES) return@synchronized null
        Snapshot(
            sessionsJson = sessions,
            pendingCount = (parsed.int("pendingCount") ?: 0).coerceAtLeast(0),
            at = parsed.long("at") ?: 0L,
        )
    }

    /** How many Macs currently have a stored copy. */
    fun entryCount(): Int = synchronized(lock) { entries().size }

    data class Snapshot(val sessionsJson: String, val pendingCount: Int, val at: Long)

    /** A host ID is hashed into the file name so it can never escape the cache directory. */
    private fun file(hostID: String): File =
        File(directory, Identity.digest(hostID.toByteArray(Charsets.UTF_8)) + ".json")

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

    /** Least recently written copies go first; the copy just saved is always kept. */
    private fun prune(keep: File) {
        val sorted = entries().sortedBy { it.lastModified() }
        var excess = sorted.size - MAX_HOSTS
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

    private fun ownerOnlyDirectory(directory: File) {
        directory.setReadable(false, false)
        directory.setWritable(false, false)
        directory.setExecutable(false, false)
        directory.setReadable(true, true)
        directory.setWritable(true, true)
        directory.setExecutable(true, true)
    }

    private companion object {
        const val MAX_HOSTS = 8
        const val MAX_PAYLOAD_BYTES = 512 * 1024

        /**
         * The payload is embedded as a JSON string, so the stored file can be larger
         * than the payload. A control character escapes to six ASCII bytes at worst.
         */
        const val MAX_FILE_BYTES = MAX_PAYLOAD_BYTES * 6 + 4 * 1024
    }
}
