package com.cmuxremote.mobile.data

import android.content.Context
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.security.KeyVault
import java.io.File

/**
 * The paired Macs and this device's identity, kept in app-private storage.
 *
 * The saved grants contain each Mac's private key, so the list is sealed by a
 * non-exportable Keystore key before it reaches the filesystem. A file that
 * cannot be opened is discarded rather than trusted; a plaintext file written by
 * an earlier build is read once and rewritten sealed.
 */
class ConnectionStore(private val context: Context) {
    private val vault = KeyVault(context)
    private val file: File
        get() = File(File(context.filesDir, "connection"), "paired.json")

    private val listFile: File
        get() = File(File(context.filesDir, "connection"), "connections.json")

    private val keyFile: File
        get() = File(File(context.filesDir, "connection"), "identity.key")

    /** Every approved Mac, in the order they were added. */
    fun loadAll(): List<AuthorizedConnection> {
        val saved = runCatching {
            val text = readSealed(listFile) ?: return emptyList()
            val array = Json.parse(text) as? kotlinx.serialization.json.JsonArray ?: return emptyList()
            array.mapNotNull { entry ->
                (entry as? kotlinx.serialization.json.JsonObject)?.let(AuthorizedConnection::from)?.also { it.validate() }
            }
        }.getOrDefault(emptyList())
        if (saved.isNotEmpty()) return saved
        // A single saved Mac from an earlier build moves into the list on first load.
        val legacy = load() ?: return emptyList()
        runCatching { save(legacy) }
        return listOf(legacy)
    }

    /** Adds or replaces one Mac, keeping the others. */
    fun saveToList(connection: AuthorizedConnection) {
        connection.validate()
        val existing = loadAll().filterNot { it.host.id == connection.host.id } + connection
        saveList(existing)
    }

    fun removeHost(hostID: String) {
        val remaining = loadAll().filterNot { it.host.id == hostID }
        if (remaining.isEmpty()) {
            listFile.delete()
        } else {
            saveList(remaining)
        }
    }

    private fun saveList(connections: List<AuthorizedConnection>) {
        writeSealed(listFile, Json.text(kotlinx.serialization.json.JsonArray(connections.map { it.toJson() })))
    }

    fun load(): AuthorizedConnection? = runCatching {
        val text = readSealed(file) ?: return null
        val connection = AuthorizedConnection.from(Json.parse(text) as? kotlinx.serialization.json.JsonObject ?: return null)
        connection.validate()
        connection
    }.getOrNull()

    fun save(connection: AuthorizedConnection) {
        connection.validate()
        writeSealed(file, Json.text(connection.toJson()))
    }

    fun clear() {
        file.delete()
        listFile.delete()
    }

    /**
     * Loads this device's Ed25519 key, creating it on first use.
     *
     * The key is wrapped by a non-exportable Keystore key; a plaintext key left by
     * an earlier build is moved into the vault and then deleted.
     */
    fun privateKey(): ByteArray {
        val legacy = runCatching { keyFile.readBytes() }.getOrNull()
        if (legacy != null && legacy.size == 32) {
            // Keep the same identity: the saved grant is bound to this key.
            runCatching { vault.adopt(legacy) }.onSuccess { keyFile.delete() }
            return legacy
        }
        return vault.loadOrCreate()
    }

    /** Whether the identity is wrapped by the hardware-backed keystore, for the connection page. */
    fun keyBacking(): String = vault.backing()

    /** Discards the identity too, for a deliberate "pair again from scratch". */
    fun clearIdentity() {
        keyFile.delete()
        vault.reset()
        vault.resetSealed()
        clear()
    }

    /** Reads a sealed file, accepting an unsealed one written before this build. */
    private fun readSealed(target: File): String? {
        val bytes = runCatching { target.readBytes() }.getOrNull() ?: return null
        if (bytes.isEmpty()) return null
        if (!bytes.startsWith(MAGIC)) return String(bytes, Charsets.UTF_8)
        // The magic is not authentication: a Keystore invalidation makes this throw,
        // which the caller turns into "no saved Macs" instead of trusting bytes.
        val plain = vault.openSealed(bytes.copyOfRange(MAGIC.size, bytes.size))
        return String(plain, Charsets.UTF_8)
    }

    private fun writeSealed(target: File, text: String) {
        val directory = target.parentFile ?: return
        directory.mkdirs()
        directory.setReadable(false, false)
        directory.setExecutable(false, false)
        directory.setReadable(true, true)
        directory.setExecutable(true, true)
        target.writeBytes(MAGIC + vault.seal(text.toByteArray(Charsets.UTF_8)))
        target.setReadable(false, false)
        target.setWritable(false, false)
        target.setReadable(true, true)
        target.setWritable(true, true)
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }

    private companion object {
        /** Bumped only if the envelope layout changes. */
        val MAGIC = "CMUXENC1".toByteArray(Charsets.US_ASCII)
    }
}
