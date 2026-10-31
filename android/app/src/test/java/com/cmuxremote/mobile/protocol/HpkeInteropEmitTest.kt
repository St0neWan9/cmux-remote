package com.cmuxremote.mobile.protocol

import org.bouncycastle.crypto.hpke.HPKE
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Writes one packet this client's HPKE produces, so the Swift side can try to
 * open it. Runs only when CMUX_HPKE_EMIT names an output file.
 */
class HpkeInteropEmitTest {
    @Test
    fun emitSealedPacketForSwift() {
        val target = System.getenv("CMUX_HPKE_EMIT")
        assumeTrue("Set CMUX_HPKE_EMIT to an output file.", !target.isNullOrBlank())

        val hpke: HPKE = HpkeSession.suite()
        val client = hpke.generatePrivateKey()
        val host = hpke.generatePrivateKey()
        val clientPublic = hpke.serializePublicKey(client.public)
        val hostPublic = hpke.serializePublicKey(host.public)
        val clientPrivate = hpke.serializePrivateKey(client.private)
        val hostPrivate = hpke.serializePrivateKey(host.private)

        val info = "cmux-link/3/interop/client-host"
        val session = HpkeSession.client(client, hostPublic, info.toByteArray(Charsets.US_ASCII))
        val packet = session.seal("hello interop".toByteArray(Charsets.US_ASCII))

        File(target!!).writeText(
            listOf(
                Identity.base64(clientPrivate),
                Identity.base64(clientPublic),
                Identity.base64(hostPrivate),
                Identity.base64(hostPublic),
                Identity.base64(packet.encapsulatedKey ?: ByteArray(0)),
                Identity.base64(packet.ciphertext),
                info,
            ).joinToString("\n") + "\n",
        )
    }
}
