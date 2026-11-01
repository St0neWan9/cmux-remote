package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.HpkeSession
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
) {
    private val wanted = Channel<List<String>>(Channel.CONFLATED)
    private var supervisor: Job? = null
    private var link: LinkClient? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        supervisor = scope.launch {
            var attempt = 0
            while (isActive && running) {
                existing?.let { already ->
                    resubscribe(already)
                    already.failure()
                    return@launch
                }
                lateinit var client: LinkClient
                client = LinkClient(
                    host = connection.host,
                    endpoint = connection.endpoint,
                    privateKey = connection.privateKey,
                    clientID = connection.clientID,
                    agreementKey = HpkeSession.generateKeyPair(),
                    onEvent = { event -> onChanged(client.subscriptionPaths[event.id] ?: "") },
                )
                link = client
                try {
                    client.connect()
                    client.epoch = epoch()
                    attempt = 0
                    resubscribe(client)
                } catch (_: Exception) {
                    // The next loop iteration redials; HTTPS polling carries the UI meanwhile.
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
                link = null
                attempt++
                delay(backoffMillis(attempt))
            }
        }
    }

    fun stop() {
        running = false
        link?.close()
        link = null
        supervisor?.cancel()
        supervisor = null
    }

    /** Replaces the set of resources this link watches. */
    fun watch(paths: List<String>) {
        wanted.trySend(paths)
    }

    private fun backoffMillis(attempt: Int): Long {
        val seconds = minOf(30L, 1L shl minOf(attempt, 5))
        return seconds * 1000
    }

    private var subscribed: Map<String, String> = emptyMap()

    private fun resubscribe(client: LinkClient, paths: List<String> = lastPaths) {
        lastPaths = paths
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

    private var lastPaths: List<String> = emptyList()
}
