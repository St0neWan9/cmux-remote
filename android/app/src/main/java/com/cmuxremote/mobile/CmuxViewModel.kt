package com.cmuxremote.mobile

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cmuxremote.mobile.bridge.Enrollment
import com.cmuxremote.mobile.bridge.LiveUpdates
import com.cmuxremote.mobile.bridge.PendingEnrollment
import com.cmuxremote.mobile.data.BackgroundTaskCache
import com.cmuxremote.mobile.data.BridgeRepository
import com.cmuxremote.mobile.data.ChatMessage
import com.cmuxremote.mobile.data.ConnectionStore
import com.cmuxremote.mobile.data.ConversationMerge
import com.cmuxremote.mobile.data.ConversationSnapshot
import com.cmuxremote.mobile.data.ConversationStore
import com.cmuxremote.mobile.data.FeedItem
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.ui.ModelOption
import com.cmuxremote.mobile.ui.StartRoot
import com.cmuxremote.mobile.ui.StartWorkspace
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.EnrollmentStatus
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.string
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** What the shell shows: pairing, waiting for the owner, or a paired Mac's conversations. */
sealed interface ShellState {
    data object Restoring : ShellState
    data class Pairing(val busy: Boolean = false, val error: String? = null, val notice: String? = null) : ShellState
    data class AwaitingOwner(val requestID: String, val hostName: String, val expiresIn: String) : ShellState
    data class Connected(
        val hostName: String,
        val sessions: List<HostedSession>,
        val pending: List<FeedItem> = emptyList(),
        /** Every Feed event, so the Feed page can switch between pending and history. */
        val feed: List<FeedItem> = emptyList(),
        /** Pending count from the last background pass, until a live read replaces it. */
        val cachedPending: Int = 0,
        /** Workspace id to its title, for the list's groups. */
        val workspaces: Map<String, String> = emptyMap(),
        /** Every approved Mac, for the list's tabs. */
        val hosts: List<Pair<String, String>> = emptyList(),
        val canStart: Boolean = false,
        val loading: Boolean = false,
        val error: String? = null,
    ) : ShellState
    data class Failed(val code: String, val message: String) : ShellState
}

/** A message opened on its own page to select part of it. */
data class SelectTextRequest(val title: String, val text: String, val monospaced: Boolean)

/** The project page of one conversation. */
data class ProjectUi(
    val changes: List<com.cmuxremote.mobile.data.ProjectChange> = emptyList(),
    val selectedPath: String? = null,
    val text: com.cmuxremote.mobile.data.ProjectText? = null,
    val loading: Boolean = true,
    val error: String? = null,
)

/** One recorded image opened from a conversation. */
data class ImageUi(val reference: com.cmuxremote.mobile.data.ImageReference, val bytes: ByteArray? = null, val loading: Boolean = true, val error: String? = null)

/** One open conversation: its history, draft and the turn state. */
data class ConversationUi(
    val session: SessionDescriptor,
    val messages: List<ChatMessage>,
    val draft: String = "",
    val loading: Boolean = true,
    val sending: Boolean = false,
    val preview: String? = null,
    val error: String? = null,
    val hasMore: Boolean = false,
    val loadingOlder: Boolean = false,
    val feed: List<FeedItem> = emptyList(),
    /** When the running turn began, for the live timer. */
    val turnStartedAt: java.time.Instant? = null,
    /** Transcript generation the loaded history belongs to. */
    val generation: String = "",
    val images: List<com.cmuxremote.mobile.data.ImageReference> = emptyList(),
    val backgroundTasks: List<com.cmuxremote.mobile.data.BackgroundTaskInfo> = emptyList(),
    /** Timing anchors per prompt, so a finished reply shows its own duration. */
    val responses: List<com.cmuxremote.mobile.data.ResponseTiming> = emptyList(),
    /** Total recorded running time and the turns that contributed it. */
    val recordedRunSeconds: Double? = null,
    val recordedTurnCount: Int = 0,
    /** The model the transcript last reported. */
    val agentModel: String? = null,
    /** A prompt sent but not yet seen in the transcript, shown as its own bubble. */
    val outgoing: String? = null,
    val outgoingFailed: Boolean = false,
)

/** One conversation together with the Mac it lives on. */
data class HostedSession(
    val hostID: String,
    val hostName: String,
    val session: SessionDescriptor,
)

/** The new-conversation page: an approved workspace, a folder, an agent and a first message. */
data class StartUi(
    val workspaces: List<StartWorkspace> = emptyList(),
    val selectedWorkspace: StartWorkspace? = null,
    val roots: List<StartRoot> = emptyList(),
    val selectedRoot: StartRoot? = null,
    val agents: List<String> = listOf("claude", "codex"),
    val agent: String = "claude",
    val prompt: String = "",
    val busy: Boolean = false,
    val error: String? = null,
    val notice: String? = null,
)

/** A complete tool record open in its own page, paged from the transcript. */
data class ToolDetailUi(
    val messageID: String,
    val field: String,
    val text: String = "",
    val offset: Int = 0,
    val total: Int = 0,
    val generation: String = "",
    val contentID: String? = null,
    val loading: Boolean = true,
    val error: String? = null,
    /** Offsets already read, so the page can step back without losing text. */
    val previousOffsets: List<Int> = emptyList(),
) {
    val hasMore: Boolean get() = offset > 0
    val hasPrevious: Boolean get() = previousOffsets.isNotEmpty()
}

/** One detached task's own record, read on demand and paged from the beginning. */
data class TaskUi(
    val task: com.cmuxremote.mobile.data.BackgroundTaskInfo,
    val text: String? = null,
    val loading: Boolean = true,
    val error: String? = null,
    val nextOffset: Int? = null,
    val loadingMore: Boolean = false,
)

class CmuxViewModel(application: Application) : AndroidViewModel(application) {
    private val store = ConnectionStore(application)
    /** Every page of every conversation read so far, on this phone only. */
    private val conversations = ConversationStore(application)
    /** The last page of each background task opened, so its sheet is never blank. */
    private val taskCache = BackgroundTaskCache(java.io.File(application.filesDir, "BackgroundTasks"))
    private val _shell = MutableStateFlow<ShellState>(ShellState.Restoring)
    val shell: StateFlow<ShellState> = _shell.asStateFlow()
    private val _conversation = MutableStateFlow<ConversationUi?>(null)
    val conversation: StateFlow<ConversationUi?> = _conversation.asStateFlow()
    /** The open conversation's identity: one Mac plus one session id. */
    private val _selectedKey = MutableStateFlow<String?>(null)
    val selectedKey: StateFlow<String?> = _selectedKey.asStateFlow()
    private val _feedOpen = MutableStateFlow(false)
    val feedOpen: StateFlow<Boolean> = _feedOpen.asStateFlow()
    private val _project = MutableStateFlow<ProjectUi?>(null)
    val project: StateFlow<ProjectUi?> = _project.asStateFlow()
    private val _image = MutableStateFlow<ImageUi?>(null)
    val image: StateFlow<ImageUi?> = _image.asStateFlow()
    private val _models = MutableStateFlow<List<ModelOption>>(emptyList())
    val models: StateFlow<List<ModelOption>> = _models.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    /** Whether this device may reopen an ended conversation. */
    private val _canStart = MutableStateFlow(false)
    val canStart: StateFlow<Boolean> = _canStart.asStateFlow()
    /** List controls: search, sort, workspace filter and collapsed groups, persisted per device. */
    private val prefs = application.getSharedPreferences("cmux-list", android.content.Context.MODE_PRIVATE)
    private val speech = com.cmuxremote.mobile.speech.SpeechInput(application)
    private var voiceJob: Job? = null
    private val _voiceListening = MutableStateFlow(false)
    val voiceListening: StateFlow<Boolean> = _voiceListening.asStateFlow()
    private val _voiceError = MutableStateFlow<String?>(null)
    val voiceError: StateFlow<String?> = _voiceError.asStateFlow()

    /** Dictation only edits the draft; sending stays an explicit action. */
    fun toggleVoice() {
        if (_voiceListening.value) {
            val text = speech.finish()
            _voiceListening.value = false
            voiceJob?.cancel(); voiceJob = null
            if (text.isNotBlank()) draft((conversation.value?.draft ?: "").let { existing ->
                if (existing.isBlank()) text else existing.trimEnd() + " " + text
            })
            return
        }
        _voiceError.value = null
        voiceJob = viewModelScope.launch {
            _voiceListening.value = true
            val result = speech.start()
            _voiceListening.value = false
            if (result.error != null) _voiceError.value = result.error
            if (result.partial.isNotBlank()) {
                draft((conversation.value?.draft ?: "").let { existing ->
                    if (existing.isBlank()) result.partial.trim() else existing.trimEnd() + " " + result.partial.trim()
                })
            }
        }
    }
    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()
    private val _sortByTime = MutableStateFlow(prefs.getString("sort", "workspace") == "time")
    val sortByTime: StateFlow<Boolean> = _sortByTime.asStateFlow()
    private val _workspaceFilter = MutableStateFlow<String?>(null)
    val workspaceFilter: StateFlow<String?> = _workspaceFilter.asStateFlow()
    private val _collapsed = MutableStateFlow(
        prefs.getString("collapsed", "").orEmpty().split("\n").filter { it.isNotEmpty() }.toSet(),
    )
    val collapsed: StateFlow<Set<String>> = _collapsed.asStateFlow()
    private val _statusFilter = MutableStateFlow(0)
    val statusFilter: StateFlow<Int> = _statusFilter.asStateFlow()
    private val _hostFilter = MutableStateFlow<String?>(null)
    val hostFilter: StateFlow<String?> = _hostFilter.asStateFlow()
    private val _sidebarOpen = MutableStateFlow(false)
    val sidebarOpen: StateFlow<Boolean> = _sidebarOpen.asStateFlow()
    /** Adding another Mac from the list, over the list that stays visible behind it. */
    private val _addingDevice = MutableStateFlow(false)
    val addingDevice: StateFlow<Boolean> = _addingDevice.asStateFlow()
    /**
     * Pairing progress while a Mac is already paired. It is kept apart from [shell]
     * so asking for another Mac never replaces the conversations already on screen.
     */
    private val _pairing = MutableStateFlow<ShellState?>(null)
    val pairing: StateFlow<ShellState?> = _pairing.asStateFlow()
    /** Whether the last connection probe reached the Mac, and whether one has run. */
    private val _reachable = MutableStateFlow(false)
    val reachable: StateFlow<Boolean> = _reachable.asStateFlow()
    private val _probed = MutableStateFlow(false)
    val probed: StateFlow<Boolean> = _probed.asStateFlow()
    private val _timingOpen = MutableStateFlow(false)
    val timingOpen: StateFlow<Boolean> = _timingOpen.asStateFlow()
    private val _connectionOpen = MutableStateFlow(false)
    val connectionOpen: StateFlow<Boolean> = _connectionOpen.asStateFlow()
    private val _diagnosticsOpen = MutableStateFlow(false)
    val diagnosticsOpen: StateFlow<Boolean> = _diagnosticsOpen.asStateFlow()
    private val _selectText = MutableStateFlow<SelectTextRequest?>(null)
    val selectText: StateFlow<SelectTextRequest?> = _selectText.asStateFlow()
    private val _backgroundSync = MutableStateFlow(prefs.getBoolean("backgroundSync", true))
    val backgroundSync: StateFlow<Boolean> = _backgroundSync.asStateFlow()
    private val _connection = MutableStateFlow<AuthorizedConnection?>(null)
    val connection: StateFlow<AuthorizedConnection?> = _connection.asStateFlow()

    fun setAddingDevice(value: Boolean) {
        _addingDevice.value = value
        if (value) {
            _pairing.value = ShellState.Pairing()
        } else {
            poll?.cancel()
            _pairing.value = null
        }
    }

    /** How the identity key is currently protected, for the connection page. */
    val keyBacking: String get() = store.keyBacking()

    /**
     * Probes the Mac again so the connection page can say whether it answers.
     * The probe is one signed read; it grants nothing.
     */
    fun refreshConnection() {
        val current = repository
        if (current == null) {
            _reachable.value = false
            _probed.value = true
            return
        }
        _probed.value = false
        viewModelScope.launch {
            _reachable.value = runCatching {
                kotlinx.coroutines.withTimeout(8_000) { current.probe() }
            }.isSuccess
            _probed.value = true
        }
    }

    /** The status bar's retry: probe again, then re-read whatever page is on screen. */
    fun retryConnection() {
        refreshConnection()
        viewModelScope.launch {
            if (_conversation.value != null) reloadOpen() else refresh()
        }
    }

    /** Whether reads are currently routed through the Mac's relay. */
    val overRelay: Boolean get() = repository?.overRelay == true

    fun openTiming() { _timingOpen.value = true }
    fun closeTiming() { _timingOpen.value = false }
    fun openConnection() { _connectionOpen.value = true }
    fun closeConnection() { _connectionOpen.value = false }
    fun openDiagnostics() { _diagnosticsOpen.value = true }
    fun closeDiagnostics() { _diagnosticsOpen.value = false }
    fun showText(title: String, text: String, monospaced: Boolean) { _selectText.value = SelectTextRequest(title, text, monospaced) }
    fun closeText() { _selectText.value = null }
    fun setBackgroundSync(value: Boolean) {
        _backgroundSync.value = value
        prefs.edit().putBoolean("backgroundSync", value).apply()
        if (value) com.cmuxremote.mobile.background.BackgroundSync.schedule(getApplication()) else com.cmuxremote.mobile.background.BackgroundSync.cancel(getApplication())
    }

    /** Forgets one Mac. The Mac still lists this device until the owner revokes it there. */
    fun removeMac(hostID: String? = null) {
        val id = hostID ?: hosts.firstOrNull()?.id ?: return
        val removed = hosts.firstOrNull { it.id == id }
        removed?.repository?.relayLink?.close()
        store.removeHost(id)
        // Removing a Mac removes the conversations it let this phone read.
        removed?.let {
            val scope = storeScope(it.connection)
            conversations.remove(scope)
            taskCache.remove(scope)
        } ?: run {
            conversations.remove(id)
            taskCache.remove(id)
        }
        hosts.removeAll { it.id == id }
        _conversation.value = null
        if (hosts.isEmpty()) {
            com.cmuxremote.mobile.background.BackgroundSync.cancel(getApplication())
            live?.stop(); live = null
            repository = null
            _connection.value = null
            store.clear()
            _shell.value = ShellState.Pairing()
            return
        }
        if (repository === hosts.firstOrNull()?.repository) { /* keeps the first Mac's link */ }
        repository = hosts.first().repository
        _connection.value = hosts.first().connection
        refresh()
    }

    fun search(text: String) { _query.value = text }

    fun setSortByTime(value: Boolean) {
        _sortByTime.value = value; prefs.edit().putString("sort", if (value) "time" else "workspace").apply()
    }

    fun setWorkspaceFilter(id: String?) { _workspaceFilter.value = id }

    fun setStatusFilter(index: Int) { _statusFilter.value = index }

    fun setHostFilter(id: String?) { _hostFilter.value = id }

    fun setSidebar(open: Boolean) { _sidebarOpen.value = open }

    fun toggleCollapsed(key: String) {
        val next = _collapsed.value.toMutableSet().apply { if (!add(key)) remove(key) }
        _collapsed.value = next; prefs.edit().putString("collapsed", next.sorted().joinToString("\n")).apply()
    }
    /** Images prepared for the next send: file name to base64 payload. */
    private val _pendingImages = MutableStateFlow<List<Pair<String, String>>>(emptyList())
    val pendingImages: StateFlow<List<Pair<String, String>>> = _pendingImages.asStateFlow()
    private val _task = MutableStateFlow<TaskUi?>(null)
    val task: StateFlow<TaskUi?> = _task.asStateFlow()
    private val _toolDetail = MutableStateFlow<ToolDetailUi?>(null)
    val toolDetail: StateFlow<ToolDetailUi?> = _toolDetail.asStateFlow()
    private val _start = MutableStateFlow<StartUi?>(null)
    val start: StateFlow<StartUi?> = _start.asStateFlow()

    /** One approved Mac and its own repository. */
    private class HostRuntime(val connection: AuthorizedConnection, val repository: BridgeRepository) {
        val id: String get() = connection.host.id
        val name: String get() = connection.host.name
    }

    /** The Macs advertising themselves on this network while a pairing page is open. */
    private val discovery = com.cmuxremote.mobile.bridge.BridgeDiscovery(application)
    private val _discovered = MutableStateFlow<List<com.cmuxremote.mobile.bridge.DiscoveredBridge>>(emptyList())
    val discovered: StateFlow<List<com.cmuxremote.mobile.bridge.DiscoveredBridge>> = _discovered.asStateFlow()

    fun startDiscovery() {
        discovery.start { values -> _discovered.value = values }
    }

    fun stopDiscovery() {
        discovery.stop()
        _discovered.value = emptyList()
    }

    /** Macs already paired here, so a nearby list can mark them instead of offering them. */
    fun approvedHostIDs(): Set<String> = hosts.map { it.id }.toSet()

    private val hosts = mutableListOf<HostRuntime>()
    private var repository: BridgeRepository? = null
    private var poll: Job? = null
    private var live: LiveUpdates? = null
    /** Debug-only: dial the relay even when the LAN answers, to test that path. */
    var forceRelay: Boolean = false
    private var liveRefresh: Job? = null
    private var pollLoop: Job? = null
    /** Fills the stored copy backwards while its page is open. */
    private var backfill: Job? = null
    /** Automatic earlier-page loads wait this long; a pull does not. */
    private var nextOlderAt = 0L
    /** A burst of live notifications writes the stored copy at most this often. */
    private val lastStoredAt = mutableMapOf<String, Long>()

    init {
        restore()
    }

    fun restore() {
        val saved = store.loadAll()
        if (saved.isEmpty()) {
            _shell.value = ShellState.Pairing()
            return
        }
        hosts.clear()
        saved.forEach { connection ->
            runCatching { BridgeRepository.open(connection) }.onSuccess { hosts += HostRuntime(connection, it) }
        }
        // A build before scoped caches keyed by host alone; those copies are dropped.
        viewModelScope.launch(Dispatchers.IO) {
            saved.forEach { conversations.remove(it.host.id) }
        }
        val primary = hosts.firstOrNull()
        if (primary == null) {
            _shell.value = ShellState.Pairing()
            return
        }
        connect(primary.connection)
    }

    /** Pairs from a scanned or pasted v2 enrollment code, then waits for the owner. */
    fun pair(code: String) {
        beginPairing {
            var enrollment = Enrollment.begin(code, store.privateKey())
            val status = try {
                enrollment.submit()
            } catch (error: ProtocolException) {
                // A Bridge older than this client cannot decode the "android" kind and
                // closes the request; the iPhone kind means the same thing to it.
                if (error.code != "invalid_enrollment") throw error
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                    "enrollment",
                    "Bridge does not accept the android kind; retrying as iphone",
                )
                enrollment = Enrollment.begin(code, store.privateKey(), clientKind = "iphone")
                enrollment.submit()
            }
            enrollment to status
        }
    }

    /** Pairs with a Mac found on the local network; the owner still has to approve it. */
    fun pairDiscovered(bridge: com.cmuxremote.mobile.bridge.DiscoveredBridge) {
        beginPairing {
            val enrollment = Enrollment.beginDiscovered(bridge.endpoint, bridge.host, store.privateKey())
            enrollment to enrollment.submit()
        }
    }

    /**
     * Runs one enrollment: create the pending request, wait for the owner's
     * approval, and save the grant. A poll is cancelled with the page.
     */
    private fun beginPairing(make: suspend () -> Pair<PendingEnrollment, EnrollmentStatus>) {
        poll?.cancel()
        publishPairing(ShellState.Pairing(busy = true))
        poll = viewModelScope.launch {
            var pending: PendingEnrollment? = null
            try {
                val (enrollment, first) = make()
                pending = enrollment
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                    "enrollment",
                    "request sent to ${enrollment.bootstrap.host.name} (${enrollment.bootstrap.host.id.take(8)})",
                )
                if (first.state == "approved") {
                    finish(enrollment, first)
                    return@launch
                }
                publishPairing(
                    ShellState.AwaitingOwner(
                        requestID = enrollment.request.requestID,
                        hostName = enrollment.bootstrap.host.name,
                        expiresIn = "",
                    ),
                )
                repeat(200) {
                    if (!isActive) return@launch
                    delay(1500)
                    val status = enrollment.status()
                    if (status.state == "approved") {
                        finish(enrollment, status)
                        return@launch
                    }
                    if (status.state == "denied" || status.state == "cancelled" || status.state == "expired" || status.state == "revoked") {
                        publishPairing(
                            ShellState.Failed(
                                "enrollment_" + status.state,
                                "The Mac did not approve this device.",
                            ),
                        )
                        return@launch
                    }
                }
                publishPairing(ShellState.Failed("enrollment_expired", "The approval window closed. Start pairing again on the Mac."))
            } catch (error: ProtocolException) {
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: "Pairing failed."))
                pending?.cancel()
            } catch (error: Exception) {
                // A pairing failure is worth one line: the code, never the key or the request body.
                android.util.Log.w("cmux-pair", "pairing failed: " + error.javaClass.name + " " + (error.message ?: ""))
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: ("配对失败（" + error.javaClass.simpleName + "）")))
                pending?.cancel()
            }
        }
    }

    /** Routes pairing progress to the overlay when another Mac is already paired. */
    private fun publishPairing(state: ShellState) {
        if (_pairing.value != null || (_addingDevice.value && hosts.isNotEmpty())) {
            _pairing.value = state
        } else {
            _shell.value = state
        }
    }

    fun cancelPairing() {
        poll?.cancel()
        if (_pairing.value != null) {
            _pairing.value = null
            _addingDevice.value = false
        } else {
            _shell.value = ShellState.Pairing()
        }
    }

    private fun finish(enrollment: PendingEnrollment, status: EnrollmentStatus) {
        val grant = enrollment.grant(status)
        val connection = AuthorizedConnection(
            host = enrollment.bootstrap.host,
            endpoint = enrollment.bootstrap.endpoint,
            privateKey = store.privateKey(),
            clientID = enrollment.request.clientID,
            scope = grant.scope,
            grantSignature = status.grantSignature ?: "",
            grant = grant,
        )
        connection.validate()
        // A second Mac joins the list; the first stays where it is.
        store.saveToList(connection)
        if (hosts.none { it.id == connection.host.id }) {
            runCatching { BridgeRepository.open(connection) }.onSuccess { hosts += HostRuntime(connection, it) }
        }
        com.cmuxremote.mobile.data.Diagnostics.log(
            com.cmuxremote.mobile.data.Diagnostics.Level.Info,
            "enrollment",
            "approved by ${connection.host.name}; ${connection.scope.capabilities.size} capabilities",
        )
        _pairing.value = null
        _addingDevice.value = false
        connect(connection)
    }

    private fun connect(connection: AuthorizedConnection) {
        _connection.value = connection
        _reachable.value = true
        _probed.value = true
        if (hosts.none { it.id == connection.host.id }) {
            runCatching { BridgeRepository.open(connection) }.onSuccess { hosts += HostRuntime(connection, it) }
        }
        _canStart.value = connection.scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationStart)
        if (_backgroundSync.value) com.cmuxremote.mobile.background.BackgroundSync.schedule(getApplication())
        val repository = BridgeRepository.open(connection)
        this.repository = repository
        // Show the last background snapshot immediately; the live read replaces it.
        _shell.value = cachedState() ?: ShellState.Connected(connection.host.name, emptyList(), loading = true)
        startLive(connection)
        viewModelScope.launch {
            // A Mac reachable only through its relay carries every read on the link.
            if ((forceRelay || !lanReachable(repository, connection)) && connection.endpoint.relay != null) {
                val relayed = dialRelay(connection, repository) ?: return@launch
                repository.useRelayLink(relayed.link)
                live?.stop()
                live = LiveUpdates(
                    connection,
                    viewModelScope,
                    { path -> onLiveChange(path) },
                    { repository.epoch() },
                    existing = relayed.link,
                )
                live?.start()
                live?.watch(listPaths())
            }
            refresh()
        }
    }

    /**
     * The session lists and pending counts background sync last stored, for a first
     * frame before any live read. The cache is convenience only: it is replaced by
     * every successful refresh and never authorizes anything.
     */
    private fun cachedState(): ShellState.Connected? {
        if (hosts.isEmpty()) return null
        val cache = com.cmuxremote.mobile.background.SessionSnapshotCache(getApplication())
        val entries = hosts.mapNotNull { host ->
            cache.load(host.id)?.let { snapshot -> host to snapshot }
        }
        if (entries.isEmpty()) return null
        val sessions = entries.flatMap { (host, snapshot) ->
            BridgeRepository.decodeSessions(snapshot.sessionsJson).map { HostedSession(host.id, host.name, it) }
        }
        if (sessions.isEmpty() && entries.all { it.second.pendingCount == 0 }) return null
        return ShellState.Connected(
            hostName = hosts.first().name,
            sessions = sessions,
            cachedPending = entries.sumOf { it.second.pendingCount },
            hosts = hosts.map { it.id to it.name },
            loading = true,
            canStart = _canStart.value,
        )
    }

    private suspend fun lanReachable(repository: BridgeRepository, connection: AuthorizedConnection): Boolean =
        runCatching { kotlinx.coroutines.withTimeout(6_000) { repository.epoch(); true } }.getOrDefault(false)

    private class Relayed(val link: com.cmuxremote.mobile.bridge.LinkClient)

    /** Dials the host's relay and returns the authenticated link, or null. */
    private suspend fun dialRelay(connection: AuthorizedConnection, repository: BridgeRepository): Relayed? {
        val relay = connection.endpoint.relay ?: return null
        val link = com.cmuxremote.mobile.bridge.LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = com.cmuxremote.mobile.protocol.HpkeSession.generateKeyPair(),
            onEvent = { event -> onLiveChange(event.id) },
        )
        return try {
            link.connectForcedRelay(relay)
            // The epoch is read over the link itself: the LAN may be the unreachable path.
            link.epoch = repository.withLink(link) { epoch() }
            Relayed(link)
        } catch (error: Exception) {
            null
        }
    }

    /// Change notifications arrive over the encrypted link; HTTPS polling stays as
    /// the fallback for a Bridge that cannot open one.
    /**
     * The encrypted link carries change notifications; HTTPS polling stays as the
     * fallback for a Bridge whose link cannot open. The link never authorizes
     * anything: every refresh is a signed read.
     */
    private fun startLive(connection: AuthorizedConnection) {
        live?.stop()
        val repository = repository
        val updates = LiveUpdates(connection, viewModelScope, { path -> onLiveChange(path) }, { repository?.epoch() ?: "" })
        live = updates
        updates.start()
        updates.watch(listPaths())
    }

    /** Resources watched while the list is on screen. */
    private fun listPaths(): List<String> = listOf("/v2/sessions", "/v2/feed")

    private fun onLiveChange(path: String) {
        // Coalesce bursts: a running turn fires several notifications per second.
        liveRefresh?.cancel()
        liveRefresh = viewModelScope.launch {
            kotlinx.coroutines.delay(250)
            if (path.startsWith("/v2/sessions/") && path.endsWith("/history")) {
                reloadOpen()
            } else {
                refresh()
                if (_conversation.value != null) reloadOpen()
            }
        }
    }

    private fun watchOpenSession(sessionID: String?) {
        pollLoop?.cancel()
        val paths = buildList {
            addAll(listPaths())
            if (sessionID != null) add("/v2/sessions/$sessionID/history")
        }
        live?.watch(paths)
        // A slow poll covers a Bridge whose link stayed closed; it is cancelled with the page.
        pollLoop = viewModelScope.launch {
            while (isActive) {
                // A floor under a Bridge whose link stays closed; the link notifies sooner.
                delay(if (sessionID == null) 30_000 else 15_000)
                if (sessionID != null) reloadOpen() else refresh()
            }
        }
    }

    fun refresh() {
        if (hosts.isEmpty()) return
        viewModelScope.launch {
            val shell = _shell.value as? ShellState.Connected
                ?: ShellState.Connected(hosts.first().name, emptyList())
            _shell.value = shell.copy(loading = true, error = null)
            val cache = com.cmuxremote.mobile.background.SessionSnapshotCache(getApplication())
            val previousByHost = shell.sessions.groupBy { it.hostID }
                .mapValues { (_, values) -> values.map { it.session } }
            val results: List<HostRead> = kotlinx.coroutines.coroutineScope {
                hosts.map { host ->
                    async(kotlinx.coroutines.Dispatchers.IO) {
                        // An empty session list is a normal state, not a failed read.
                        val read = runCatching { host.repository.sessions() }
                        val extras = runCatching {
                            host.repository.workspaces().toMap() to host.repository.feed()
                        }.getOrDefault(emptyMap<String, String>() to emptyList())
                        val stored = if (read.isFailure) cache.load(host.id) else null
                        val cached = stored?.let { BridgeRepository.decodeSessions(it.sessionsJson) }.orEmpty()
                        val sessions = read.getOrNull()
                            ?: cached.ifEmpty { previousByHost[host.id].orEmpty() }
                        val pendingCount = extras.second.count { it.status == "pending" }
                        if (read.isSuccess) {
                            runCatching {
                                cache.save(
                                    host.id,
                                    BridgeRepository.encodeSessions(sessions),
                                    pendingCount,
                                    System.currentTimeMillis(),
                                )
                            }
                        }
                        HostRead(
                            host = host,
                            sessions = sessions,
                            workspaces = extras.first,
                            feed = extras.second,
                            reached = read.isSuccess,
                            cachedPending = if (read.isSuccess) 0 else stored?.pendingCount ?: 0,
                        )
                    }
                }.map { it.await() }
            }
            val sessions = results.flatMap { read -> read.sessions.map { HostedSession(read.host.id, read.host.name, it) } }
            val workspaces = results.flatMap { it.workspaces.entries }.associate { it.key to it.value }
            val feed = results.flatMap { it.feed }
            val pending = feed.filter { it.status == "pending" }
            val anyReached = results.any { it.reached }
            _reachable.value = anyReached
            _probed.value = true
            _shell.value = ShellState.Connected(
                hostName = hosts.first().name,
                sessions = sessions,
                pending = pending,
                cachedPending = results.sumOf { it.cachedPending },
                feed = feed,
                workspaces = workspaces,
                hosts = hosts.map { it.id to it.name },
                loading = false,
                error = if (anyReached) null else getApplication<Application>().getString(R.string.error_connection),
                canStart = _canStart.value,
            )
        }
    }

    /** One Mac's list and pending items, plus whether its read answered. */
    private class HostRead(
        val host: HostRuntime,
        val sessions: List<SessionDescriptor>,
        val workspaces: Map<String, String>,
        val feed: List<FeedItem>,
        val reached: Boolean,
        val cachedPending: Int,
    )

    fun open(hosted: HostedSession) {
        val host = hosts.firstOrNull { it.id == hosted.hostID } ?: return
        repository = host.repository
        _selectedKey.value = hosted.hostID + ":" + hosted.session.id
        open(hosted.session)
    }

    fun open(session: SessionDescriptor) {
        val current = repository ?: return
        backfill?.cancel()
        // Selection is host-qualified: two Macs may report the same session id.
        _selectedKey.value = hosts.firstOrNull { it.repository === current }?.let { it.id + ":" + session.id }
        watchOpenSession(session.id)
        val scope = storeScope(current.connection)
        _conversation.value = ConversationUi(session = session, messages = emptyList())
        viewModelScope.launch {
            // What was read last is shown whole, before any round trip; the read
            // that follows either confirms it or replaces its generation.
            val stored = withContext(Dispatchers.IO) {
                runCatching { conversations.restore(scope, session.id) }.getOrNull()
            }
            if (stored != null) {
                _conversation.update { ui ->
                    if (ui?.session?.id != session.id) ui else ui.copy(
                        messages = stored.messages,
                        loading = false,
                        hasMore = stored.hasMore,
                        images = stored.images,
                        backgroundTasks = stored.backgroundTasks,
                        responses = stored.responses,
                        recordedRunSeconds = stored.recordedRunSeconds,
                        recordedTurnCount = stored.recordedTurnCount,
                        agentModel = stored.agentModel,
                        generation = stored.generation,
                        turnStartedAt = if (ui.session.working) stored.currentTurnStartedAt else null,
                    )
                }
            }
            try {
                val snapshot = current.history(session.id)
                val preview = runCatching { current.preview(session.id) }.getOrNull()
                val feed = runCatching { current.feed() }.getOrDefault(emptyList())
                _conversation.update { ui ->
                    if (ui?.session?.id != session.id) ui
                    else applySnapshot(ui, snapshot, ui.session, feed).copy(preview = preview, loading = false)
                }
                lastStoredAt[scope + ":" + session.id] = System.currentTimeMillis()
                withContext(Dispatchers.IO) {
                    runCatching {
                        conversations.save(snapshot, scope, session.id, complete = !snapshot.hasMore)
                    }
                }
                if (snapshot.hasMore) {
                    snapshot.messages.firstOrNull()?.seq?.let { oldest ->
                        startBackfill(current, scope, session.id, oldest)
                    }
                }
            } catch (error: ProtocolException) {
                noteReadFailure(error)
                _conversation.update { it?.copy(loading = false, error = error.userMessage()) }
            } catch (error: Exception) {
                noteReadFailure(error)
                _conversation.update { it?.copy(loading = false, error = error.userMessage() ?: "History could not be read.") }
            }
        }
    }

    /**
     * Fills the stored copy backwards while the page is open, so reading back
     * through a long conversation never asks the Mac again. Bounded to 64 pages;
     * anything longer is filled the next time it is opened.
     */
    private fun startBackfill(
        current: BridgeRepository,
        scope: String,
        sessionID: String,
        fromSeq: Int,
    ) {
        backfill?.cancel()
        backfill = viewModelScope.launch {
            var before = fromSeq
            repeat(BACKFILL_PAGES) {
                if (!isActive) return@launch
                val page = runCatching {
                    current.history(sessionID, beforeSeq = before, limit = 100)
                }.getOrNull() ?: return@launch
                withContext(Dispatchers.IO) {
                    runCatching {
                        conversations.save(page, scope, sessionID, complete = !page.hasMore)
                    }
                }
                val next = page.messages.filter { it.seq < before }.minOfOrNull { it.seq }
                    ?: return@launch
                if (next >= before) return@launch
                before = next
                if (!page.hasMore) return@launch
            }
        }
    }

    /**
     * Stored conversations belong to one host and one device identity: an explicit
     * re-pair gets a new client id and must not see the previous grant's copies.
     */
    private fun storeScope(connection: AuthorizedConnection): String =
        connection.host.id + ":" + connection.clientID

    /** A refusal from the Bridge still means it answered; only a transport failure is offline. */
    private fun noteReadFailure(error: Throwable) {
        _reachable.value = error is ProtocolException &&
            error.code !in setOf("connection_failed", "link_failed", "timeout")
        _probed.value = true
    }

    /**
     * Joins a newest-page read with what the page already shows. A replaced
     * generation replaces the conversation instead of mixing two reads.
     */
    private fun applySnapshot(
        ui: ConversationUi,
        snapshot: ConversationSnapshot,
        session: SessionDescriptor,
        feed: List<FeedItem>,
    ): ConversationUi {
        val continues = ui.generation.isNotEmpty() && ui.generation == snapshot.generation
        val messages = if (continues) ConversationMerge.messages(ui.messages, snapshot.messages) else snapshot.messages
        val responses = if (continues) ConversationMerge.responses(ui.responses, snapshot.responses) else snapshot.responses
        val images = if (continues) {
            ConversationMerge.images(ui.images, snapshot.images, snapshot.generation)
        } else {
            snapshot.images
        }
        return ui.copy(
            messages = messages,
            session = session,
            loading = false,
            // A read that answered replaces a lost-link message left on the page.
            error = null,
            hasMore = snapshot.hasMore,
            feed = feed,
            images = images,
            backgroundTasks = if (snapshot.backgroundTasksPresent) snapshot.backgroundTasks else ui.backgroundTasks,
            responses = responses,
            recordedRunSeconds = snapshot.recordedRunSeconds,
            recordedTurnCount = snapshot.recordedTurnCount,
            agentModel = snapshot.agentModel ?: ui.agentModel,
            generation = snapshot.generation,
            turnStartedAt = if (session.working) snapshot.currentTurnStartedAt else null,
            outgoing = ui.outgoing?.takeIf { text ->
                messages.none { message ->
                    message.kind == "prose" && message.role == "user" && message.text.trim() == text.trim()
                }
            },
        )
    }

    fun close() {
        backfill?.cancel()
        _conversation.value = null
        _selectedKey.value = null
        _feedOpen.value = false
        watchOpenSession(null)
    }

    fun openFeed() {
        _feedOpen.value = true
    }

    fun closeFeed() {
        _feedOpen.value = false
    }

    fun openProject() = openProjectAt(null)

    /** Opens the project page at a file a tool referenced, or at its first change. */
    fun openProjectAt(path: String?) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        _project.value = ProjectUi()
        viewModelScope.launch {
            try {
                val changes = current.project().changes(conversation.session.id)
                _project.value = ProjectUi(changes = changes, loading = false)
                val target = path ?: changes.firstOrNull()?.path
                target?.let { selectChange(it) }
            } catch (error: ProtocolException) {
                _project.value = ProjectUi(loading = false, error = error.userMessage())
            }
        }
    }

    fun closeProject() {
        _project.value = null
    }

    fun selectChange(path: String) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        val project = _project.value ?: return
        _project.value = project.copy(selectedPath = path, loading = true, error = null)
        viewModelScope.launch {
            try {
                val reader = current.project()
                val text = runCatching { reader.diff(conversation.session.id, path) }
                    .recoverCatching { reader.file(conversation.session.id, path) }
                    .getOrThrow()
                _project.update { it?.copy(text = text, loading = false) }
            } catch (error: ProtocolException) {
                _project.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    fun openImage(reference: com.cmuxremote.mobile.data.ImageReference) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        _image.value = ImageUi(reference)
        viewModelScope.launch {
            try {
                val bytes = current.image(conversation.session.id, reference)
                _image.value = ImageUi(reference, bytes = bytes, loading = false)
            } catch (error: ProtocolException) {
                _image.value = ImageUi(reference, loading = false, error = error.userMessage())
            }
        }
    }

    fun closeImage() {
        _image.value = null
    }

    fun openTask(info: com.cmuxremote.mobile.data.BackgroundTaskInfo) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        val scope = storeScope(current.connection)
        val sessionID = conversation.session.id
        _task.value = TaskUi(info)
        viewModelScope.launch {
            // The last read is shown first; the read below confirms or replaces it.
            val cached = withContext(Dispatchers.IO) {
                runCatching { taskCache.load(scope, sessionID, info.id) }.getOrNull()
            }
            if (cached != null) {
                _task.update { ui ->
                    if (ui?.task?.id != info.id) ui
                    else ui.copy(text = cached.text, nextOffset = cached.nextOffset, loading = false)
                }
            }
            try {
                val page = current.task(sessionID, info.id)
                _task.update { ui ->
                    if (ui?.task?.id != info.id) ui
                    else ui.copy(text = page.text, loading = false, nextOffset = page.nextOffset)
                }
                withContext(Dispatchers.IO) {
                    runCatching {
                        taskCache.save(
                            BackgroundTaskCache.Entry(
                                tool = info.tool,
                                summary = info.summary,
                                running = info.running,
                                text = page.text,
                                nextOffset = page.nextOffset,
                                storedAt = System.currentTimeMillis(),
                            ),
                            scope,
                            sessionID,
                            info.id,
                        )
                    }
                }
            } catch (error: ProtocolException) {
                _task.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    /** Appends the next bounded page of a detached task's record. */
    fun loadMoreTask() {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        val value = _task.value ?: return
        val offset = value.nextOffset ?: return
        if (value.loadingMore) return
        val scope = storeScope(current.connection)
        val sessionID = conversation.session.id
        _task.update { it?.copy(loadingMore = true) }
        viewModelScope.launch {
            try {
                val page = current.task(sessionID, value.task.id, offset)
                val combined = (value.text ?: "") + page.text
                _task.update {
                    it?.copy(
                        text = combined,
                        nextOffset = page.nextOffset,
                        loadingMore = false,
                    )
                }
                withContext(Dispatchers.IO) {
                    runCatching {
                        taskCache.save(
                            BackgroundTaskCache.Entry(
                                tool = value.task.tool,
                                summary = value.task.summary,
                                running = value.task.running,
                                text = combined,
                                nextOffset = page.nextOffset,
                                storedAt = System.currentTimeMillis(),
                            ),
                            scope,
                            sessionID,
                            value.task.id,
                        )
                    }
                }
            } catch (error: ProtocolException) {
                _task.update { it?.copy(loadingMore = false, error = error.userMessage()) }
            }
        }
    }

    fun closeTask() {
        _task.value = null
    }

    fun openToolDetail(messageID: String, field: String) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        _toolDetail.value = ToolDetailUi(messageID = messageID, field = field)
        viewModelScope.launch {
            try {
                val page = current.toolDetail(
                    conversation.session.id, messageID, field,
                    conversation.generation.ifEmpty { "current" },
                )
                _toolDetail.value = ToolDetailUi(
                    messageID = messageID,
                    field = field,
                    text = page.text,
                    offset = page.nextOffset ?: 0,
                    total = page.totalCharacters,
                    generation = page.generation,
                    contentID = page.contentID,
                    loading = false,
                )
            } catch (error: ProtocolException) {
                _toolDetail.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    fun loadMoreToolDetail() {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        val value = _toolDetail.value ?: return
        if (value.offset <= 0 || value.loading) return
        _toolDetail.update { it?.copy(loading = true) }
        viewModelScope.launch {
            try {
                val page = current.toolDetail(
                    conversation.session.id, value.messageID, value.field, value.generation, value.offset, value.contentID,
                )
                _toolDetail.update {
                    it?.copy(
                        text = it.text + page.text,
                        offset = page.nextOffset ?: 0,
                        total = page.totalCharacters,
                        contentID = page.contentID,
                        loading = false,
                        previousOffsets = it.previousOffsets + value.offset,
                    )
                }
            } catch (error: ProtocolException) {
                _toolDetail.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    /** Steps back one page of a complete tool record. */
    fun previousToolDetailPage() {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        val value = _toolDetail.value ?: return
        val previous = value.previousOffsets.lastOrNull() ?: return
        _toolDetail.update { it?.copy(loading = true) }
        viewModelScope.launch {
            try {
                val page = current.toolDetail(
                    conversation.session.id, value.messageID, value.field, value.generation, previous, value.contentID,
                )
                _toolDetail.update {
                    it?.copy(
                        text = page.text,
                        offset = page.nextOffset ?: 0,
                        total = page.totalCharacters,
                        contentID = page.contentID,
                        loading = false,
                        previousOffsets = it.previousOffsets.dropLast(1),
                    )
                }
            } catch (error: ProtocolException) {
                _toolDetail.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    fun closeToolDetail() {
        _toolDetail.value = null
    }

    fun openStart() = openStart(workspaceID = null)

    /** Starts from one workspace's own group in the list. */
    fun startInWorkspace(workspaceID: String) = openStart(workspaceID = workspaceID)

    private fun openStart(workspaceID: String?) {
        val current = repository ?: return
        _start.value = StartUi(busy = true)
        viewModelScope.launch {
            try {
                val workspaces = current.workspaces().map { (id, title) -> StartWorkspace(id, title) }
                _start.update { it?.copy(workspaces = workspaces, busy = false) }
                val preferred = workspaces.firstOrNull { it.id == workspaceID } ?: workspaces.firstOrNull()
                preferred?.let { pickStartWorkspace(it) }
            } catch (error: ProtocolException) {
                _start.update { it?.copy(busy = false, error = error.userMessage()) }
            }
        }
    }

    fun closeStart() {
        _start.value = null
    }

    fun pickStartWorkspace(workspace: StartWorkspace) {
        val current = repository ?: return
        _start.update { it?.copy(selectedWorkspace = workspace, roots = emptyList(), selectedRoot = null, busy = true, error = null) }
        viewModelScope.launch {
            try {
                val roots = current.startRoots(workspace.id).map { (id, path) -> StartRoot(id, path) }
                _start.update { it?.copy(roots = roots, selectedRoot = roots.firstOrNull(), busy = false) }
            } catch (error: ProtocolException) {
                _start.update { it?.copy(busy = false, error = error.userMessage(), notice = "这个工作区没有可以新建会话的目录。") }
            }
        }
    }

    fun pickStartRoot(root: StartRoot) = _start.update { it?.copy(selectedRoot = root) }

    fun pickStartAgent(agent: String) = _start.update { it?.copy(agent = agent) }

    fun startPrompt(text: String) = _start.update { it?.copy(prompt = text) }

    /** Opens a terminal running the fixed agent command; the phone never chooses a command. */
    fun startSession() {
        val current = repository ?: return
        val state = _start.value ?: return
        val workspace = state.selectedWorkspace ?: return
        val root = state.selectedRoot ?: return
        val known = (_shell.value as? ShellState.Connected)?.sessions?.map { it.session.id }?.toSet() ?: emptySet()
        _start.update { it?.copy(busy = true, error = null, notice = null) }
        viewModelScope.launch {
            try {
                val receipt = current.startSession(workspace.id, root.id, "", state.agent, state.prompt.ifBlank { null })
                val surface = (receipt as? kotlinx.serialization.json.JsonObject)?.get("surface_id")?.toString()?.trim('"')
                _start.update { it?.copy(busy = false, notice = "终端已经打开，正在等待会话出现…") }
                repeat(20) {
                    delay(1500)
                    refresh()
                    val sessions = (_shell.value as? ShellState.Connected)?.sessions ?: return@repeat
                    // Only a conversation that did not exist before this start counts.
                    val match = sessions.firstOrNull { hosted ->
                        val session = hosted.session
                        session.id !in known &&
                            session.workspaceID?.lowercase() == workspace.id.lowercase() &&
                            (surface == null || session.surfaceID?.lowercase() == surface.lowercase())
                    }
                    if (match != null) {
                        _start.value = null
                        open(match)
                        return@launch
                    }
                }
                _start.update { it?.copy(notice = "终端已打开；会话还没有出现，稍后刷新列表。") }
            } catch (error: ProtocolException) {
                _start.update { it?.copy(busy = false, error = error.userMessage()) }
            }
        }
    }

    fun loadModels() {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        if (!conversation.session.writable) return
        viewModelScope.launch {
            runCatching { current.models(conversation.session.id) }
                .onSuccess { list -> _models.value = list.map { (id, label) -> ModelOption(id, label) } }
        }
    }

    /**
     * A switch Claude Code asked to confirm. The Bridge refused it once; the page
     * asks the reader, then retries the same switch with `confirm`.
     */
    private val _modelConfirm = MutableStateFlow<ModelOption?>(null)
    val modelConfirm: StateFlow<ModelOption?> = _modelConfirm.asStateFlow()

    fun switchModel(option: ModelOption) = switchModel(option, confirmed = false)

    fun confirmModelSwitch() {
        val option = _modelConfirm.value ?: return
        _modelConfirm.value = null
        switchModel(option, confirmed = true)
    }

    fun cancelModelSwitch() {
        _modelConfirm.value = null
    }

    private fun switchModel(option: ModelOption, confirmed: Boolean) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        _busy.value = true
        viewModelScope.launch {
            try {
                current.switchModel(conversation.session.id, option.id, confirm = confirmed)
                _conversation.update { it?.copy(error = null) }
                reloadOpen()
            } catch (error: ProtocolException) {
                // A long conversation needs the reader's explicit confirmation; the
                // refusal changed nothing, so the same switch can be retried.
                if (error.code == "model_confirm_required" && !confirmed) {
                    _modelConfirm.value = option
                } else {
                    _conversation.update { it?.copy(error = error.userMessage()) }
                }
            } finally {
                _busy.value = false
            }
        }
    }

    fun rename(title: String) {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        viewModelScope.launch {
            try {
                current.rename(conversation.session.id, title)
                _conversation.update { it?.copy(session = it.session.copy(title = title)) }
                refresh()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    /** Reopens an ended Agent session in a new terminal of its own workspace. */
    fun resume() {
        val current = repository ?: return
        val conversation = _conversation.value ?: return
        _busy.value = true
        viewModelScope.launch {
            try {
                current.resume(conversation.session.id)
                refresh()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            } finally {
                _busy.value = false
            }
        }
    }

    fun attachImage(fileName: String, base64: String) {
        if (_pendingImages.value.size >= 4) return
        _pendingImages.update { it + (fileName to base64) }
    }

    /** Puts a quoted reply ahead of the draft, as the iPhone's footer does. */
    fun appendQuote(text: String) {
        val value = _conversation.value ?: return
        val quoted = text.split("\n").joinToString("\n") { "> " + it }
        _conversation.update { it?.copy(draft = quoted + "\n\n" + value.draft) }
    }

    fun removeImage(index: Int) {
        _pendingImages.update { list -> list.filterIndexed { position, _ -> position != index } }
    }

    /** Sends the draft with prepared images. */
    fun sendWithImages(prepared: List<Pair<String, String>>) {
        val current = repository ?: return
        val value = _conversation.value ?: return
        if (value.sending) return
        val text = value.draft.trim()
        viewModelScope.launch {
            _conversation.update { it?.copy(sending = true, error = null, outgoing = text, outgoingFailed = false) }
            try {
                val operation = java.util.UUID.randomUUID().toString()
                _pendingOperation.value = operation
                prefs.edit().putString("pendingOperation", operation).apply()
                current.sendWithImages(value.session.id, text, prepared, operation)
                _pendingOperation.value = null
                prefs.edit().remove("pendingOperation").apply()
                _pendingImages.value = emptyList()
                _conversation.update { it?.copy(sending = false, draft = "") }
                reloadOpen()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = true, error = error.userMessage()) }
            } catch (error: Exception) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = true, error = error.userMessage() ?: "图片没有确认送达。") }
            }
        }
    }

    fun draft(text: String) {
        _conversation.update { it?.copy(draft = text) }
    }

    /** The send whose outcome is unknown, kept across restarts so it is inspected, never replayed. */
    private val _pendingOperation = MutableStateFlow(prefs.getString("pendingOperation", null))
    val pendingOperation: StateFlow<String?> = _pendingOperation.asStateFlow()

    /** Asks the Mac what became of a send whose reply was lost. */
    fun checkPendingSend() {
        val current = repository ?: return
        val id = _pendingOperation.value ?: return
        viewModelScope.launch {
            try {
                val status = current.operation(id)
                val state = status.string("state") ?: "outcome_unknown"
                if (state == "accepted") {
                    _pendingOperation.value = null
                    prefs.edit().remove("pendingOperation").apply()
                    _conversation.update { it?.copy(error = null) }
                    reloadOpen()
                } else {
                    _conversation.update { it?.copy(error = "这条消息的结果仍未确认，请先在 Mac 上查看。") }
                }
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    /** Forgets the unknown send after the reader has looked at the Mac. */
    fun acknowledgePendingSend() {
        _pendingOperation.value = null
        prefs.edit().remove("pendingOperation").apply()
    }

    /** Sends the draft once; a failed send keeps the text so it can be inspected, never auto-retried. */
    /** Pages in earlier history, keeping the rows already read. */
    /**
     * Pages in earlier messages.
     *
     * A pull is the reader asking, so it is not filtered by what the page believes:
     * a stale `hasMore` is exactly what once made the gesture do nothing, and asking
     * again costs one request that answers honestly. Automatic loads keep the 0.8 s
     * pause so a scroll at the top cannot chain pages while the list is laying out.
     */
    fun loadOlder(pull: Boolean = false) {
        val current = repository ?: return
        val value = _conversation.value ?: return
        if (value.loadingOlder) return
        val now = System.currentTimeMillis()
        if (!pull) {
            if (!value.hasMore) return
            if (now < nextOlderAt) return
        }
        val oldest = value.messages.firstOrNull()?.seq ?: return
        nextOlderAt = now + OLDER_PAUSE_MS
        _conversation.update { it?.copy(loadingOlder = true) }
        val scope = storeScope(current.connection)
        val sessionID = value.session.id
        viewModelScope.launch {
            // The flag answers "is a page in flight", so it clears however this read ends.
            try {
                // An earlier page already stored never asks the Mac again.
                val stored = withContext(Dispatchers.IO) {
                    runCatching {
                        conversations.page(scope, sessionID, beforeSeq = oldest, limit = 40)
                    }.getOrNull()?.takeIf { it.generation == value.generation }
                }
                val page = stored ?: runCatching {
                    current.history(sessionID, beforeSeq = oldest, limit = 40)
                }.getOrNull()
                if (page == null) return@launch
                // A page from a replaced transcript belongs to another seq space; refresh instead
                // of mixing it in, and do not store it over the current generation.
                if (page.generation != value.generation) {
                    reloadOpen()
                    return@launch
                }
                if (stored == null) {
                    withContext(Dispatchers.IO) {
                        runCatching {
                            conversations.save(page, scope, sessionID, complete = !page.hasMore)
                        }
                    }
                }
                _conversation.update { ui ->
                    if (ui?.session?.id != sessionID) {
                        ui
                    } else {
                        ui.copy(
                            messages = ConversationMerge.messages(ui.messages, page.messages),
                            responses = ConversationMerge.responses(ui.responses, page.responses),
                            images = ConversationMerge.images(ui.images, page.images, page.generation),
                            // The page that answered decides; asking again after a false is
                            // still allowed through a pull.
                            hasMore = page.hasMore,
                        )
                    }
                }
            } finally {
                _conversation.update {
                    if (it?.session?.id != sessionID) it else it.copy(loadingOlder = false)
                }
            }
        }
    }

    /** A pull when there is no earlier page to ask for: read the newest page again. */
    fun refreshOpen() {
        viewModelScope.launch { reloadOpen() }
    }

    fun send() {
        val current = repository ?: return
        val value = _conversation.value ?: return
        val text = value.draft.trim()
        if (_pendingImages.value.isNotEmpty()) { sendWithImages(_pendingImages.value); return }
        if (text.isEmpty() || value.sending) return
        viewModelScope.launch {
            _conversation.update { it?.copy(sending = true, error = null, outgoing = text, outgoingFailed = false) }
            val operation = java.util.UUID.randomUUID().toString()
            _pendingOperation.value = operation
            prefs.edit().putString("pendingOperation", operation).apply()
            try {
                current.send(value.session.id, text, operation)
                _pendingOperation.value = null
                prefs.edit().remove("pendingOperation").apply()
                _conversation.update { it?.copy(sending = false, draft = "") }
                reloadOpen()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = true, error = error.userMessage()) }
            } catch (error: Exception) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = true, error = error.userMessage() ?: "The prompt was not confirmed.") }
            }
        }
    }

    fun stop() = interrupt(hard = false)

    /** Hard stop ends the agent's process, not just the current turn; the UI asks first. */
    fun forceStop() = interrupt(hard = true)

    private fun interrupt(hard: Boolean) {
        val current = repository ?: return
        val value = _conversation.value ?: return
        viewModelScope.launch {
            try {
                current.interrupt(value.session.id, hard = hard)
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                    "conversation",
                    if (hard) "force stop sent ${value.session.id.take(8)}" else "stop sent ${value.session.id.take(8)}",
                )
                reloadOpen()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            } catch (error: Exception) {
                _conversation.update { it?.copy(error = error.userMessage() ?: "The stop was not confirmed.") }
            }
        }
    }

    /**
     * Answers the Feed request that a transcript question belongs to.
     *
     * The transcript gives no request id, so the prompt is matched against the
     * pending Feed items. A request with several questions is answered on the
     * Feed page, where one label per question can be collected.
     */
    fun answerQuestionFromMessage(messageID: String, selections: List<String>) {
        val value = _conversation.value ?: return
        val message = value.messages.firstOrNull { it.id == messageID } ?: return
        val prompt = message.prompt ?: message.text
        val match = value.feed.firstOrNull { item ->
            item.status == "pending" && item.questions.any { it.prompt == prompt }
        }
        if (match == null || match.questions.size != 1) {
            _feedOpen.value = true
            return
        }
        answerQuestion(match.requestID, selections)
    }

    fun answerQuestion(requestID: String, selections: List<String>) {
        val current = repository ?: return
        val kind = pendingKind(requestID)
        viewModelScope.launch {
            try {
                current.answer(requestID, kind, selections)
                reloadOpen()
                refresh()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    /** Feed decision that names the event kind and, for a plan, an optional feedback line. */
    fun decideWithKind(requestID: String, kind: String, modeAndFeedback: String) {
        val mode = modeAndFeedback.substringBefore('\u0000')
        val feedback = modeAndFeedback.substringAfter('\u0000', "").ifBlank { null }
        val current = repository ?: return
        viewModelScope.launch {
            try {
                current.reply(requestID, kind, mode, feedback)
                reloadOpen()
                refresh()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    fun decide(requestID: String, mode: String) {
        val current = repository ?: return
        val kind = pendingKind(requestID)
        viewModelScope.launch {
            try {
                current.reply(requestID, kind, mode)
                reloadOpen()
                refresh()
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    /** The kind the Bridge last reported for a pending request; a decision must name it. */
    private fun pendingKind(requestID: String): String {
        val shell = _shell.value as? ShellState.Connected
        val match = shell?.pending?.firstOrNull { it.requestID == requestID }
            ?: _conversation.value?.feed?.firstOrNull { it.requestID == requestID }
        return match?.kind?.takeIf { it.isNotBlank() } ?: "question"
    }

    /**
     * Localizes a stable error code. The Bridge's own sentence is English and is
     * only a fallback for codes this build does not know.
     */
    private fun Throwable.userMessage(): String = when (this) {
        is ProtocolException -> {
            val id = when (code) {
                "unauthorized" -> R.string.error_unauthorized
                "forbidden" -> R.string.error_unauthorized
                "revoked" -> R.string.error_revoked
                "invalid_proof" -> R.string.error_invalid_proof
                "host_changed" -> R.string.error_host_changed
                "invalid_certificate" -> R.string.error_invalid_certificate
                "connection_failed", "link_failed", "discovery_failed" -> R.string.error_connection
                "timeout" -> R.string.error_timeout
                "response_too_large" -> R.string.error_response_too_large
                "operation_not_found" -> R.string.error_operation_not_found
                "outcome_unknown" -> R.string.error_outcome_unknown
                "invalid_enrollment" -> R.string.error_invalid_enrollment
                "enrollment_pending" -> R.string.error_enrollment_pending
                "invalid_route", "invalid_response" -> R.string.error_invalid_response
                "invalid_image" -> R.string.error_invalid_image
                else -> null
            }
            id?.let { getApplication<Application>().getString(it) } ?: message ?: code
        }
        else -> message ?: javaClass.simpleName
    }

    override fun onCleared() {
        live?.stop()
        discovery.stop()
        backfill?.cancel()
        super.onCleared()
    }

    private companion object {
        /** iOS fills 64 pages; anything longer is resumed on the next open. */
        const val BACKFILL_PAGES = 64
        const val STORE_COALESCE_MS = 2_000L
        const val OLDER_PAUSE_MS = 800L
    }

    private suspend fun reloadOpen() {
        val current = repository ?: return
        val value = _conversation.value ?: return
        runCatching {
            val snapshot = current.history(value.session.id)
            val sessions = current.sessions()
            val feed = runCatching { current.feed() }.getOrDefault(emptyList())
            val refreshed = sessions.firstOrNull { it.id == value.session.id } ?: value.session
            _conversation.update { ui ->
                if (ui?.session?.id != value.session.id) ui else applySnapshot(ui, snapshot, refreshed, feed)
            }
            // Every newest-page read becomes the stored copy, so reopening never re-reads it.
            // A running turn fires several notifications per second; two seconds of
            // coalescing keeps SQLite out of the render path without going stale.
            val scope = storeScope(current.connection)
            val key = scope + ":" + value.session.id
            val now = System.currentTimeMillis()
            if (now - (lastStoredAt[key] ?: 0L) >= STORE_COALESCE_MS) {
                lastStoredAt[key] = now
                withContext(Dispatchers.IO) {
                    runCatching {
                        conversations.save(
                            snapshot,
                            scope,
                            value.session.id,
                            complete = !snapshot.hasMore,
                        )
                    }
                }
            }
            val shell = _shell.value as? ShellState.Connected
            val host = hosts.firstOrNull { it.repository === current }
            if (shell != null && host != null) {
                val hosted = sessions.map { HostedSession(host.id, host.name, it) }
                val others = shell.sessions.filterNot { it.hostID == host.id }
                _shell.value = shell.copy(sessions = others + hosted)
            }
        }
            .onSuccess {
                _reachable.value = true
                _probed.value = true
            }
            .onFailure { error -> noteReadFailure(error) }
    }
}
