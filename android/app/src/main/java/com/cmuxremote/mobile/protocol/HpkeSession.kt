package com.cmuxremote.mobile.protocol

import org.bouncycastle.crypto.AsymmetricCipherKeyPair
import org.bouncycastle.crypto.hpke.HPKE
import org.bouncycastle.crypto.hpke.HPKEContext
import org.bouncycastle.crypto.params.AsymmetricKeyParameter

/**
 * RFC 9180 authenticated HPKE, P-256 / HKDF-SHA256 / AES-256-GCM, used by the
 * encrypted link. BouncyCastle implements the standard, so this stays byte
 * compatible with CryptoKit's HPKE on the Mac.
 */
class HpkeSession private constructor(
    private val sender: HPKEContext,
    private val receiving: HPKEContext?,
    /** The encapsulation this session puts on its first packet. */
    val encapsulatedKey: ByteArray?,
) {
    private var sent = 0
    private var received = 0

    fun seal(plaintext: ByteArray): SealedPacket =
        SealedPacket(if (sent == 0) encapsulatedKey else null, sender.seal(ByteArray(0), plaintext).also { sent++ })

    fun open(packet: SealedPacket): ByteArray {
        if (received > 0 && packet.encapsulatedKey != null) {
            throw ProtocolException("invalid_request", "Link contexts cannot be reset.", 400)
        }
        val context = receiving ?: throw ProtocolException("invalid_request", "No receiving context.", 400)
        val plaintext = try {
            context.open(ByteArray(0), packet.ciphertext)
        } catch (error: Exception) {
            throw ProtocolException("invalid_response", "The link packet could not be opened.", 502)
        }
        received++
        return plaintext
    }

    companion object {
        /** P-256, HKDF-SHA256, AES-256-GCM, authenticated mode. */
        fun suite(): HPKE = HPKE(HPKE.mode_auth, HPKE.kem_P256_SHA256, HPKE.kdf_HKDF_SHA256, HPKE.aead_AES_GCM256)

        fun generateKeyPair(): AsymmetricCipherKeyPair = suite().generatePrivateKey()

        fun publicKey(pair: AsymmetricCipherKeyPair): ByteArray = suite().serializePublicKey(pair.public)

        fun publicKeyOf(pair: AsymmetricCipherKeyPair): AsymmetricKeyParameter = pair.public

        /** The client's sending context: its own agreement key authenticates the sender. */
        fun client(
            agreementKey: AsymmetricCipherKeyPair,
            peerAgreementKey: ByteArray,
            info: ByteArray,
        ): HpkeSession {
            val hpke = suite()
            val context = hpke.setupAuthS(hpke.deserializePublicKey(peerAgreementKey), info, agreementKey)
            return HpkeSession(context, receiving = null, encapsulatedKey = context.encapsulation)
        }

        /** The client's receiving context, once the host's encapsulation arrives. */
        fun recipient(
            agreementKey: AsymmetricCipherKeyPair,
            peerAgreementKey: ByteArray,
            hostEncapsulation: ByteArray,
            info: ByteArray,
        ): HpkeSession {
            val hpke = suite()
            val context = hpke.setupAuthR(hostEncapsulation, agreementKey, info, hpke.deserializePublicKey(peerAgreementKey))
            return HpkeSession(context, receiving = context, encapsulatedKey = null)
        }
    }
}

/** One sealed packet, matching `SealedLinkPacket` on the Mac. */
data class SealedPacket(val encapsulatedKey: ByteArray?, val ciphertext: ByteArray)
