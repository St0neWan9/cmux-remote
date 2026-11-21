package dev.trenta.termremote.bridge

import dev.trenta.termremote.protocol.AuthorizedConnection
import dev.trenta.termremote.protocol.HpkeSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Keeps one encrypted link open and turns its change notifications into
 * re-reads. The link never authorizes anything: every refresh goes through the
 * signed HTTPS path, so a closed link only costs freshness.
 */
class LiveUpdates(
    private val connection: AuthorizedConnection,
    private val scope: CoroutineScope,
    private val onChanged: (path: String) -> Unit,
    private val epoch: suspend () -> String,
    /** An already authenticated link, when the relay was dialled before this started. */
    private val existing: LinkClient? = null,
    /** Called once a newly dialled link is authenticated and has its verified epoch. */
    private val onLinkConnected: ((LinkClient, String) -> Unit)? = null,
    /** Called when a managed link drops or is stopped so callers can detach it if still active. */
    private val onLinkClosed: ((LinkClient) -> Unit)? = null,
) {
    private val wanted = Channel<List<String>>(Channel.CONFLATED)
    private var supervisor: Job? = null
    @Volatile private var link: LinkClient? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        supervisor = scope.launch {
            var attempt = 0
            var connectedOnce = false
            var pendingExisting = existing
            while (isActive && running) {
                val client: LinkClient
                if (pendingExisting != null) {
                    client = pendingExisting
                    pendingExisting = null
                    link = client
                    subscribed = emptyMap()
                    if (!client.isOpen) {
                        client.close()
                        onLinkClosed?.invoke(client)
                        link = null
                        continue
                    }
                    attempt = 0
                    connectedOnce = true
                    resubscribe(client)
                } else {
                    lateinit var fresh: LinkClient
                    fresh = LinkClient(
                        host = connection.host,
                        endpoint = connection.endpoint,
                        privateKey = connection.privateKey,
                        clientID = connection.clientID,
                        agreementKey = HpkeSession.generateKeyPair(),
                        onEvent = { event -> onChanged(fresh.subscriptionPaths[event.id] ?: "") },
                    )
                    client = fresh
                    link = client
                    subscribed = emptyMap()
                    val connected = try {
                        client.connect()
                        val resolvedEpoch = if (client.dialedViaRelay) client.fetchEpoch() else epoch()
                        client.epoch = resolvedEpoch
                        attempt = 0
                        connectedOnce = true
                        onLinkConnected?.invoke(client, resolvedEpoch)
                        resubscribe(client)
                        true
                    } catch (_: Exception) {
                        // Do not fall through to client.failure(): a failed dial never posts
                        // to failures, so waiting there would hang this supervisor forever.
                        false
                    }
                    if (!connected) {
                        client.close()
                        onLinkClosed?.invoke(client)
                        link = null
                        attempt++
                        delay(backoffMillis(attempt))
                        continue
                    }
                }
                // Re-subscribe whenever the wanted set changes, until the link dies.
                val watcher = scope.launch {
                    for (paths in wanted) {
                        if (!client.isOpen) break
                        resubscribe(client, paths)
                    }
                }
                client.failure()
                watcher.cancel()
                client.close()
                onLinkClosed?.invoke(client)
                link = null
                subscribed = emptyMap()
                attempt++
                if (connectedOnce) {
                    // A link that worked and dropped is redialed at once, as iOS does.
                    connectedOnce = false
                    attempt = 1
                } else {
                    delay(backoffMillis(attempt))
                }
            }
        }
    }

    fun stop() {
        running = false
        val current = link
        link = null
        subscribed = emptyMap()
        current?.close()
        if (current != null) onLinkClosed?.invoke(current)
        supervisor?.cancel()
        supervisor = null
    }

    /** Replaces the set of resources this link watches. */
    fun watch(paths: List<String>) {
        lastPaths = paths
        wanted.trySend(paths)
    }

    private fun backoffMillis(attempt: Int): Long {
        val seconds = minOf(32L, 2L shl minOf(attempt, 4))
        return seconds * 1000
    }

    private var subscribed: Map<String, String> = emptyMap()

    private fun resubscribe(client: LinkClient, paths: List<String> = lastPaths) {
        lastPaths = paths
        if (!client.isOpen) return
        val next = paths.toSet()
        val current = subscribed.toMutableMap()
        for ((path, id) in subscribed) {
            if (path !in next) {
                client.cancel(id)
                current.remove(path)
            }
        }
        for (path in next) {
            if (!current.containsKey(path)) {
                current[path] = client.subscribe(path)
            }
        }
        subscribed = current
    }

    @Volatile private var lastPaths: List<String> = emptyList()
}
