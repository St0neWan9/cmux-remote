package com.cmuxremote.mobile.data

import android.content.Context
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.security.KeyVault
import java.io.File

/**
 * The paired Mac and this device's identity, kept in app-private storage.
 *
 * The private key never leaves the app's data directory and is never logged. A
 * file that fails its own signature check is discarded rather than trusted.
 */
class ConnectionStore(private val context: Context) {
    private val vault = KeyVault(context)
    private val file: File
        get() = File(File(context.filesDir, "connection"), "paired.json")

    private val keyFile: File
        get() = File(File(context.filesDir, "connection"), "identity.key")

    /** Every approved Mac, in the order they were added. */
    fun loadAll(): List<AuthorizedConnection> {
        val listFile = File(File(context.filesDir, "connection"), "connections.json")
        val saved = runCatching {
            val text = listFile.readText()
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
            File(File(context.filesDir, "connection"), "connections.json").delete()
        } else {
            saveList(remaining)
        }
    }

    private fun saveList(connections: List<AuthorizedConnection>) {
        val directory = File(context.filesDir, "connection").apply { mkdirs() }
        val file = File(directory, "connections.json")
        file.writeText(Json.text(kotlinx.serialization.json.JsonArray(connections.map { it.toJson() })))
        file.setReadable(false, false); file.setReadable(true, true)
    }

    fun load(): AuthorizedConnection? {
        val saved = runCatching {
            val text = file.readText()
            val connection = AuthorizedConnection.from(Json.parse(text) as? kotlinx.serialization.json.JsonObject ?: return null)
            connection.validate()
            connection
        }.getOrNull() ?: return null
        return saved
    }

    fun save(connection: AuthorizedConnection) {
        connection.validate()
        val directory = file.parentFile ?: return
        directory.mkdirs()
        directory.setReadable(false, false)
        directory.setExecutable(false, false)
        directory.setReadable(true, true)
        directory.setExecutable(true, true)
        file.writeText(Json.text(connection.toJson()))
        file.setReadable(false, false)
        file.setReadable(true, true)
    }

    fun clear() {
        file.delete()
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
        clear()
    }

}
