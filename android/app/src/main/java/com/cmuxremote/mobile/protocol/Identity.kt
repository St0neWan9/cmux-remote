package com.cmuxremote.mobile.protocol

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** Ed25519 identities and SHA-256 names shared by the Bridge and every client. */
object Identity {
    private val random = SecureRandom()

    fun generatePrivateKey(): ByteArray = ByteArray(32).also { random.nextBytes(it) }

    fun publicKey(privateKey: ByteArray): ByteArray =
        Ed25519PrivateKeyParameters(privateKey, 0).generatePublicKey().encoded

    fun publicKeyBase64(privateKey: ByteArray): String = base64(publicKey(privateKey))

    /** SHA-256 of the raw 32-byte public key, lowercase hex. */
    fun identityId(publicKeyBase64: String): String = hex(sha256(decodeBase64(publicKeyBase64, 32)))

    fun sign(message: ByteArray, privateKey: ByteArray): ByteArray {
        val signer = Ed25519Signer()
        signer.init(true, Ed25519PrivateKeyParameters(privateKey, 0))
        signer.update(message, 0, message.size)
        return signer.generateSignature()
    }

    fun verify(message: ByteArray, signature: ByteArray, publicKeyBase64: String): Boolean {
        if (signature.size != 64) return false
        return try {
            val verifier = Ed25519Signer()
            verifier.init(false, Ed25519PublicKeyParameters(decodeBase64(publicKeyBase64, 32), 0))
            verifier.update(message, 0, message.size)
            verifier.verifySignature(signature)
        } catch (_: RuntimeException) {
            false
        }
    }

    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    fun digest(data: ByteArray): String = hex(sha256(data))

    fun hex(data: ByteArray): String = data.joinToString("") { "%02x".format(it) }

    fun base64(data: ByteArray): String = Base64.getEncoder().encodeToString(data)

    fun decodeBase64(value: String, expectedLength: Int? = null): ByteArray {
        val bytes = Base64.getDecoder().decode(value)
        if (expectedLength != null && bytes.size != expectedLength) {
            throw ProtocolException("invalid_identity", "The identity proof has the wrong size.")
        }
        return bytes
    }
}

/** A stable protocol failure with a code the UI localizes and a bounded message. */
class ProtocolException(val code: String, message: String, val status: Int = 400) : Exception(message)
