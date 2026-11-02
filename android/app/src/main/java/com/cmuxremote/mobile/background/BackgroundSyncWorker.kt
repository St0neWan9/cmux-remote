package com.cmuxremote.mobile.background

import android.content.Context
import android.os.SystemClock
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.cmuxremote.mobile.data.BridgeRepository
import com.cmuxremote.mobile.data.ConnectionStore
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.Json
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.util.concurrent.TimeUnit

/**
 * The periodic pass that keeps each Mac's session list and pending count warm while
 * the app is away, standing in for the iPhone's `BGAppRefreshTask`.
 *
 * WorkManager owns the schedule: 15 minutes is the shortest interval it offers, and
 * the system may defer a run further under Doze or battery restrictions. A pass only
 * reads: it never sends, stops, or answers anything. Every Mac is tried once, at most
 * four Macs per pass, all inside a 60 second budget.
 */
class BackgroundSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val connections = runCatching { ConnectionStore(applicationContext).loadAll() }
            .getOrDefault(emptyList())
        // Nothing paired means there is nothing to retry.
        if (connections.isEmpty()) return Result.success()

        // Children inherit the worker's cancellation, but one failed Mac must not
        // cancel the reads of the Macs after it.
        return supervisorScope {
            val workerScope = this
            workerScope.async { sync(connections) }.await()
        }
    }

    private suspend fun sync(connections: List<AuthorizedConnection>): Result {
        val cache = SessionSnapshotCache(applicationContext)
        val started = SystemClock.elapsedRealtime()
        var answered = 0
        var outOfBudget = false

        val completed = withTimeoutOrNull(TOTAL_BUDGET_MS) {
            for (connection in connections) {
                currentCoroutineContext().ensureActive()
                val remaining = TOTAL_BUDGET_MS - (SystemClock.elapsedRealtime() - started)
                if (remaining <= 0) return@withTimeoutOrNull false

                // A Mac that fails or times out is skipped; it is not retried in this pass.
                val read = withTimeoutOrNull(minOf(PER_HOST_BUDGET_MS, remaining)) { readHost(connection) }
                if (read != null) {
                    cache.save(
                        hostID = connection.host.id,
                        sessionsJson = encodeSessions(read.sessions),
                        pendingCount = read.pendingCount,
                        at = System.currentTimeMillis(),
                    )
                    answered++
                }
            }
            true
        }
        if (completed != true) outOfBudget = true
        com.cmuxremote.mobile.data.Diagnostics.log(
            com.cmuxremote.mobile.data.Diagnostics.Level.Info,
            "sync",
            "background pass read $answered of ${connections.size} Macs in ${SystemClock.elapsedRealtime() - started} ms",
        )

        return when {
            answered > 0 -> Result.success()
            // A run that spent its whole budget has nothing left to spend on a retry.
            outOfBudget -> Result.success()
            else -> Result.retry()
        }
    }

    /** Reads one Mac once. Cancellation is the worker's, never this Mac's, so it still propagates. */
    private suspend fun readHost(connection: AuthorizedConnection): HostRead? = try {
        val repository = BridgeRepository.open(connection)
        // A Mac only reachable through its relay still answers: the LAN read is
        // tried first, then the same signed requests run over the relay link.
        val lan = runCatching { repository.sessions() }
        if (lan.isSuccess) {
            readBody(repository, connection, lan.getOrThrow())
        } else {
            val link = dialRelay(connection) ?: throw (lan.exceptionOrNull() ?: IllegalStateException("unreachable"))
            try {
                repository.withLink(link) { readBody(this, connection, sessions()) }
            } finally {
                link.close()
            }
        }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }

    private suspend fun dialRelay(connection: AuthorizedConnection): com.cmuxremote.mobile.bridge.LinkClient? {
        val relay = connection.endpoint.relay ?: return null
        val link = com.cmuxremote.mobile.bridge.LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = com.cmuxremote.mobile.protocol.HpkeSession.generateKeyPair(),
            onEvent = {},
        )
        return try {
            link.connectForcedRelay(relay)
            val body = link.request("GET", "/v2/identity", null, null)
            val signed = com.cmuxremote.mobile.protocol.decodeSignedJson(String(body, Charsets.UTF_8))
            com.cmuxremote.mobile.protocol.Signer.verify(signed, "host", connection.host.publicKey)
            val announcement = com.cmuxremote.mobile.protocol.HostAnnouncement.from(
                signed.value as? kotlinx.serialization.json.JsonObject
                    ?: throw com.cmuxremote.mobile.protocol.ProtocolException("invalid_response", "The identity is not an object."),
            )
            if (announcement.host.id != connection.host.id || announcement.epoch.isBlank()) {
                throw com.cmuxremote.mobile.protocol.ProtocolException("host_changed", "The relay answered for another host.")
            }
            link.epoch = announcement.epoch
            link
        } catch (_: Exception) {
            link.close()
            null
        }
    }

    private suspend fun readBody(
        repository: BridgeRepository,
        connection: AuthorizedConnection,
        sessions: List<SessionDescriptor>,
    ): HostRead {
        val pending = readPending(repository)
        // Keep the conversations that are running or changed since this pass last
        // stored them warm, as the iPhone's background pass does.
        val store = com.cmuxremote.mobile.data.ConversationStore(applicationContext)
        val scope = connection.host.id + ":" + connection.clientID
        val prefs = applicationContext.getSharedPreferences("background-sync", android.content.Context.MODE_PRIVATE)
        val cutoff = java.time.Instant.now().minusSeconds(24 * 60 * 60)
        sessions
            .filter { session ->
                val updated = runCatching { java.time.Instant.parse(session.updatedAt) }.getOrNull()
                session.working ||
                    (updated != null && updated.isAfter(cutoff) &&
                        updated.toEpochMilli() > prefs.getLong(scope + ":" + session.id, 0L))
            }
            .sortedByDescending { it.updatedAt.orEmpty() }
            .take(BACKGROUND_SESSIONS)
            .forEach { session ->
                runCatching { repository.history(session.id) }.onSuccess { snapshot ->
                    runCatching {
                        store.save(snapshot, scope, session.id, complete = !snapshot.hasMore)
                        prefs.edit().putLong(scope + ":" + session.id, System.currentTimeMillis()).apply()
                    }
                }
            }
        return HostRead(sessions, pending)
    }

    /** A Mac without feed access still contributes its session list; only the count is lost. */
    private suspend fun readPending(repository: BridgeRepository): Int = try {
        repository.feed().count { it.status == "pending" }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        0
    }

    private fun encodeSessions(sessions: List<SessionDescriptor>): String =
        Json.text(
            JsonArray(
                sessions.map { session ->
                    buildJsonObject {
                        put("id", JsonPrimitive(session.id))
                        put("agent", JsonPrimitive(session.agent))
                        put("title", JsonPrimitive(session.title))
                        session.cwd?.let { put("cwd", JsonPrimitive(it)) }
                        session.workspaceID?.let { put("workspaceID", JsonPrimitive(it)) }
                        session.surfaceID?.let { put("surfaceID", JsonPrimitive(it)) }
                        put("state", JsonPrimitive(session.state))
                        session.updatedAt?.let { put("updatedAt", JsonPrimitive(it)) }
                        put("resumable", JsonPrimitive(session.resumable))
                    }
                },
            ),
        )

    private data class HostRead(val sessions: List<SessionDescriptor>, val pendingCount: Int)

    companion object {
        const val UNIQUE_NAME = "cmux-background-sync"

        private const val PERIOD_MINUTES = 15L
        private const val PER_HOST_BUDGET_MS = 20_000L
        private const val TOTAL_BUDGET_MS = 60_000L
        /** The iPhone's background pass keeps the newest twelve conversations. */
        private const val BACKGROUND_SESSIONS = 12

        /** Schedules the periodic pass, keeping an already-enqueued schedule untouched. */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = PeriodicWorkRequestBuilder<BackgroundSyncWorker>(PERIOD_MINUTES, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(UNIQUE_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME)
        }
    }
}

/**
 * The hook the UI calls after a Mac connects and when background refresh is toggled.
 * It delegates to [BackgroundSyncWorker] so scheduling stays in one place.
 */
object BackgroundSync {
    fun schedule(context: Context) = BackgroundSyncWorker.schedule(context)

    fun cancel(context: Context) = BackgroundSyncWorker.cancel(context)
}
