package com.cmuxremote.mobile.bridge

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * A LAN client that trusts exactly one leaf certificate, by DER SHA-256.
 *
 * The Bridge serves a self-signed certificate without a SAN, so a CA chain or a
 * hostname check would always fail. This is the same decision `PinnedSessionDelegate`
 * makes on iOS: compare the exact leaf, and check the address separately.
 */
class PinnedHttpClient(
    private val host: String,
    private val port: Int,
    certificateSHA256: String,
) {
    private val pin = certificateSHA256.lowercase()

    private val client: OkHttpClient = run {
        val manager = PinnedTrustManager(pin)
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(manager), null) }
        OkHttpClient.Builder()
            .sslSocketFactory(context.socketFactory, manager)
            .hostnameVerifier { name, session ->
                // OkHttp runs this after the trust manager; re-check the same pin and
                // address so a substituted certificate can never pass on hostname alone.
                canonical(name) == canonical(host) &&
                    runCatching {
                        val chain = session.peerCertificates
                        chain.isNotEmpty() && chain.first() is X509Certificate &&
                            manager.matchesPinned(chain.first() as X509Certificate)
                    }.getOrDefault(false)
            }
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    val baseUrl: String = "https://$host:$port"

    fun newCall(request: Request): Call = Call(client.newCall(request))

    class Call(private val call: okhttp3.Call) {
        fun execute(): Response = call.execute()
        fun cancel() = call.cancel()
    }

    private fun canonical(value: String): String {
        val trimmed = value.trim().removePrefix("[").removeSuffix("]").lowercase()
        return if (trimmed.contains(":")) trimmed.substringBefore("%") else trimmed.trimEnd('.')
    }
}

/** Rejects every chain that is not the exact pinned leaf. */
internal class PinnedTrustManager(private val pin: String) : X509TrustManager {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        throw CertificateException("Client certificates are not used.")
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("The server sent no certificate.")
        if (!matchesPinned(leaf)) throw CertificateException("The server certificate is not the paired host.")
    }

    fun matchesPinned(certificate: X509Certificate): Boolean =
        MessageDigest.isEqual(derPin(certificate).toByteArray(), pin.toByteArray())

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

    private fun derPin(certificate: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(certificate.encoded).joinToString("") { "%02x".format(it) }
}
