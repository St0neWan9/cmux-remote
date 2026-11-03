package com.cmuxremote.mobile.bridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import com.cmuxremote.mobile.data.Diagnostics
import com.cmuxremote.mobile.protocol.BridgeEndpoint
import com.cmuxremote.mobile.protocol.HostIdentity
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

private const val RESOLVE_TIMEOUT_MS = 8_000L

/** A Mac that advertises itself on the local network, with the endpoint it resolved to. */
data class DiscoveredBridge(
    val host: HostIdentity,
    val endpoint: BridgeEndpoint,
)

/** The TXT record the Bridge publishes: identity and certificate, never a secret. */
object DiscoveryTxt {
    private const val MAX_ENTRIES = 64

    fun parse(serviceName: String, attributes: Map<String, ByteArray>): HostIdentity? {
        fun field(name: String): String? =
            attributes[name]?.toString(Charsets.UTF_8)?.trim()?.takeIf { it.isNotEmpty() }

        if (field("version") != "2") return null
        val id = field("hostID") ?: return null
        val publicKey = field("publicKey") ?: return null
        val certificate = field("certificate") ?: return null
        val name = field("name") ?: return null
        val host = HostIdentity(id, publicKey, certificate, name)
        return runCatching { host.validate(); host }.getOrNull()
    }

    /** At most [MAX_ENTRIES] services are kept, so a hostile network cannot grow the list. */
    fun bounded(services: Collection<DiscoveredBridge>): List<DiscoveredBridge> =
        services.sortedBy { it.host.id }.take(MAX_ENTRIES)
}

/**
 * Browses `_cmux-remote._tcp` with Android's NSD implementation.
 *
 * Discovery is only a convenience: a found Mac still needs the owner's approval,
 * and its identity is the TXT record's, verified again when the signed bootstrap
 * is fetched.
 */
class BridgeDiscovery(private val context: Context) {
    private var nsd: NsdManager? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private var multicast: WifiManager.MulticastLock? = null
    private val found = ConcurrentHashMap<String, DiscoveredBridge>()
    private val running = AtomicBoolean(false)
    /** Only one resolve at a time: Android answers a second one with FAILURE_ALREADY_ACTIVE. */
    private var queue = Channel<NsdServiceInfo>(Channel.UNLIMITED)
    private var resumer: kotlinx.coroutines.Job? = null

    fun start(onChange: (List<DiscoveredBridge>) -> Unit) {
        if (!running.compareAndSet(false, true)) return
        val manager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
        if (manager == null) {
            running.set(false)
            Diagnostics.log(Diagnostics.Level.Warning, "discovery", "NSD is not available on this device")
            return
        }
        nsd = manager
        runCatching {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicast = wifi?.createMulticastLock("cmux-remote-discovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        queue = Channel(Channel.UNLIMITED)
        val channel = queue
        resumer = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            for (info in channel) resolve(manager, info, onChange)
        }
        val discovery = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Diagnostics.log(Diagnostics.Level.Warning, "discovery", "browse failed to start: $errorCode")
                stop()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Diagnostics.log(Diagnostics.Level.Warning, "discovery", "browse failed to stop: $errorCode")
            }

            override fun onDiscoveryStarted(serviceType: String) {
                Diagnostics.log(Diagnostics.Level.Debug, "discovery", "browsing $serviceType")
            }

            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.startsWith("_cmux-remote._tcp")) queue.trySend(service)
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                // A lost service is only stale once it stops advertising; keep what resolved.
            }
        }
        listener = discovery
        runCatching { manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery) }
            .onFailure {
                Diagnostics.log(Diagnostics.Level.Warning, "discovery", "browse could not start: ${it.javaClass.simpleName}")
                stop()
            }
    }

    /**
     * Resolves one service, then releases the queue. A resolve that never calls back would
     * otherwise block every later service, so the wait is bounded like the iOS browser's.
     */
    private suspend fun resolve(manager: NsdManager, service: NsdServiceInfo, onChange: (List<DiscoveredBridge>) -> Unit) {
        withTimeoutOrNull(RESOLVE_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                @Suppress("DEPRECATION")
                val started = runCatching {
                    manager.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                            Diagnostics.log(
                                Diagnostics.Level.Warning,
                                "discovery",
                                "resolve failed for ${info.serviceName}: $errorCode",
                            )
                            if (continuation.isActive) continuation.resume(Unit)
                        }

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = DiscoveryTxt.parse(info.serviceName, info.attributes)
                            val address = info.host?.hostAddress
                            if (host != null && address != null) {
                                val endpoint = BridgeEndpoint(address, info.port)
                                // Keyed by service, not identity: two services are two rows.
                                found[info.serviceName] = DiscoveredBridge(host, endpoint)
                                Diagnostics.log(
                                    Diagnostics.Level.Debug,
                                    "discovery",
                                    "found ${host.name} at $address:${info.port}",
                                )
                                onChange(DiscoveryTxt.bounded(found.values.toList()))
                            }
                            if (continuation.isActive) continuation.resume(Unit)
                        }
                    })
                }
                if (started.isFailure && continuation.isActive) continuation.resume(Unit)
            }
        }
    }

    fun stop() {
        running.set(false)
        resumer?.cancel()
        resumer = null
        queue.close()
        runCatching { listener?.let { nsd?.stopServiceDiscovery(it) } }
        listener = null
        nsd = null
        found.clear()
        runCatching { multicast?.release() }
        multicast = null
    }

    private companion object {
        const val SERVICE_TYPE = "_cmux-remote._tcp"
    }
}
