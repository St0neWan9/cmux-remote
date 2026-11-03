package com.cmuxremote.mobile.data

import android.os.Build
import com.cmuxremote.mobile.BuildConfig
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** A bounded in-memory log of link, dial and request events. Never holds keys, grants or bodies. */
object Diagnostics {
    enum class Level { Debug, Info, Warning, Error }

    data class Entry(val atMillis: Long, val level: Level, val category: String, val message: String)

    private const val CAPACITY = 500
    private const val MAX_MESSAGE = 512

    /** Tokens, keys, grants and signatures are long base64 or hex runs; never keep one. */
    private val SECRET = Regex("[A-Za-z0-9+/_-]{32,}={0,2}")
    private val TIME = DateTimeFormatter.ofPattern("HH:mm:ss.SSS", java.util.Locale.getDefault())
    private val STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS", java.util.Locale.getDefault())

    private val lock = Any()
    private val buffer = ArrayDeque<Entry>()

    fun log(level: Level, category: String, message: String) {
        val entry = Entry(
            atMillis = System.currentTimeMillis(),
            level = level,
            category = sanitize(category),
            message = sanitize(message).take(MAX_MESSAGE),
        )
        synchronized(lock) {
            buffer.addLast(entry)
            while (buffer.size > CAPACITY) buffer.removeFirst()
        }
    }

    /** Newest first. */
    fun entries(): List<Entry> = synchronized(lock) { buffer.toList().asReversed() }

    fun clear() {
        synchronized(lock) { buffer.clear() }
    }

    /** Header with app version and timestamp, then one `[time] [level] [category] message` line per entry. */
    fun report(): String {
        val snapshot = entries()
        val version = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        val header = "cmux-remote $version · Android ${Build.VERSION.RELEASE ?: "?"}" +
            " · ${LocalDateTime.now().format(STAMP)}"
        val lines = snapshot.map { entry ->
            "[${clock(entry.atMillis)}] [${entry.level.name.uppercase(java.util.Locale.getDefault())}] [${entry.category}] ${entry.message}"
        }
        return (listOf(header) + lines).joinToString("\n")
    }

    private fun clock(atMillis: Long): String =
        Instant.ofEpochMilli(atMillis).atZone(ZoneId.systemDefault()).format(TIME)

    private fun sanitize(text: String): String = SECRET.replace(text, "[redacted]")
}
