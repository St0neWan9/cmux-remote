package com.cmuxremote.mobile.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/** Keeps the device identity key encrypted by a non-exportable Keystore key. */
class KeyVault(private val context: Context) {
    private val file = File(context.filesDir, "identity/key.bin")
    private val random = SecureRandom()

    /** Returns the stored key, creating one on first use. */
    @Synchronized
    fun loadOrCreate(): ByteArray {
        val envelope = runCatching { file.readBytes() }.getOrNull()
        if (envelope != null) {
            val stored = runCatching { decrypt(wrappingKey(), envelope) }.getOrNull()
            if (stored != null && stored.size == KEY_SIZE) return stored
            // A restored device or invalidated key cannot open the old ciphertext.
            runCatching { keyStore().deleteEntry(ALIAS) }
        }
        val identity = ByteArray(KEY_SIZE).also { random.nextBytes(it) }
        store(encrypt(wrappingKey(), identity))
        return identity
    }

    /** Protects an existing 32-byte identity, for a key recovered from an older build. */
    @Synchronized
    fun adopt(existing: ByteArray) {
        require(existing.size == KEY_SIZE) { "An identity key is 32 bytes." }
        store(encrypt(wrappingKey(), existing))
    }

    /** Discards the keystore key and the stored ciphertext. */
    @Synchronized
    fun reset() {
        file.delete()
        runCatching { keyStore().deleteEntry(ALIAS) }
    }

    /** Whether the key is currently protected by the hardware-backed keystore (for diagnostics only). */
    fun backing(): String = runCatching {
        val key = keyStore().getKey(ALIAS, null) as? SecretKey ?: return@runCatching PLAIN
        val factory = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE_PROVIDER)
        val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
        if (info.isInsideSecureHardware) SECURE else PLAIN
    }.getOrDefault(PLAIN)

    private fun wrappingKey(): SecretKey {
        val store = keyStore()
        val existing = runCatching { store.getKey(ALIAS, null) as? SecretKey }.getOrNull()
        if (existing != null) return existing
        runCatching { store.deleteEntry(ALIAS) }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(AES_KEY_BITS)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = cipher.iv
        check(iv.size == IV_LENGTH) { "Unexpected GCM IV length" }
        // The IV is stored as the first 12 bytes, so decryption needs no extra metadata.
        return iv + cipher.doFinal(plaintext)
    }

    private fun decrypt(key: SecretKey, envelope: ByteArray): ByteArray {
        require(envelope.size > IV_LENGTH) { "Truncated identity ciphertext" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, envelope, 0, IV_LENGTH))
        return cipher.doFinal(envelope, IV_LENGTH, envelope.size - IV_LENGTH)
    }

    private fun store(envelope: ByteArray) {
        file.parentFile?.let { directory ->
            directory.mkdirs()
            directory.setReadable(false, false)
            directory.setWritable(false, false)
            directory.setExecutable(false, false)
            directory.setReadable(true, true)
            directory.setWritable(true, true)
            directory.setExecutable(true, true)
        }
        file.writeBytes(envelope)
        file.setReadable(false, false)
        file.setWritable(false, false)
        file.setReadable(true, true)
        file.setWritable(true, true)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }

    private companion object {
        const val ALIAS = "cmux-remote.identity.wrap"
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val AES_KEY_BITS = 256
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
        const val KEY_SIZE = 32
        const val SECURE = "keystore"
        const val PLAIN = "plain"
    }
}
