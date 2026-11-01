package com.cmuxremote.mobile

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cmuxremote.mobile.bridge.AndroidCapabilitiesBeforeStart
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
import com.cmuxremote.mobile.data.LegacyPairing
import com.cmuxremote.mobile.data.LegacyPairingCodec
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.ui.ModelOption
import com.cmuxremote.mobile.ui.StartRoot
import com.cmuxremote.mobile.ui.StartWorkspace
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import com.cmuxremote.mobile.protocol.EnrollmentBootstrap
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.EnrollmentStatus
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.string
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
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
    data class AwaitingOwner(
        val requestID: String,
        val hostName: String,
        val expiresIn: String,
        /** This device's own id for the request; the owner sees the same prefix. */
        val clientID: String = "",
    ) : ShellState
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

/** Dictation is idle, listening, or holding a draft the reader can use. */
enum class SpeechState { Idle, Listening, Draft }

/** A message opened on its own page to select part of it. */
data class SelectTextRequest(val title: String, val text: String, val monospaced: Boolean)

/** The project page of one conversation. */
data class ProjectUi(
    val changes: List<com.cmuxremote.mobile.data.ProjectChange> = emptyList(),
    val selectedPath: String? = null,
    val text: com.cmuxremote.mobile.data.ProjectText? = null,
    val loading: Boolean = true,
    val error: String? = null,
    /** `changes`, `diff` (the whole working tree) or `file`. */
    val mode: String = "changes",
    /** The relative path typed into the page. */
    val inputPath: String = "",
)

/** A whole activity group opened on its own page. */
data class GroupUi(val messages: List<ChatMessage>)

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
    /** The running turn is compacting its context. */
    val compacting: Boolean = false,
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
    /** The send may have reached the Mac; only the reply was lost. */
    val outgoingUnconfirmed: Boolean = false,
    /** How many images went with the pending prompt. */
    val outgoingImages: Int = 0,
    /** The Mac kept only the newest part of a very long conversation. */
    val clipped: Boolean = false,
    /** A stop was accepted; cleared when the turn actually ends or a new send starts. */
    val stopRequested: Boolean = false,
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
    /** Relative to the selected root; empty means the root itself. */
    val path: String = "",
    val folders: List<String> = emptyList(),
    val foldersTruncated: Boolean = false,
    val foldersLoading: Boolean = false,
    val foldersError: String? = null,
    val agents: List<String> = listOf("claude", "codex"),
    val agent: String = "claude",
    val prompt: String = "",
    val busy: Boolean = false,
    /** The last start's outcome is unknown; repeating it asks the Mac what happened. */
    val operation: String? = null,
    val uncertain: Boolean = false,
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
    /** An agent task's own conversation, rendered with the same rows as the timeline. */
    val messages: List<ChatMessage> = emptyList(),
    val command: String? = null,
    val totalBytes: Int? = null,
    val running: Boolean = false,
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
    /** When set, the Feed page shows one Mac's queue instead of every Mac's. */
    private val _feedHost = MutableStateFlow<String?>(null)
    val feedHost: StateFlow<String?> = _feedHost.asStateFlow()
    private val _project = MutableStateFlow<ProjectUi?>(null)
    val project: StateFlow<ProjectUi?> = _project.asStateFlow()
    private val _image = MutableStateFlow<ImageUi?>(null)
    val image: StateFlow<ImageUi?> = _image.asStateFlow()
    private val _group = MutableStateFlow<GroupUi?>(null)
    val group: StateFlow<GroupUi?> = _group.asStateFlow()
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

    /** The dictation's own draft; it reaches the composer only when the reader uses it. */
    private val _speechDraft = MutableStateFlow<String?>(null)
    val speechDraft: StateFlow<String?> = _speechDraft.asStateFlow()
    private val _speechState = MutableStateFlow(SpeechState.Idle)
    val speechState: StateFlow<SpeechState> = _speechState.asStateFlow()

    /** Dictation only edits the draft; sending stays an explicit action. */
    fun toggleVoice() {
        if (_voiceListening.value) {
            finishVoice()
            return
        }
        _voiceError.value = null
        _speechDraft.value = ""
        _speechState.value = SpeechState.Listening
        _voiceListening.value = true
        speech.onPartial = { text -> _speechDraft.value = text }
        voiceJob = viewModelScope.launch {
            val result = speech.start()
            _voiceListening.value = false
            if (result.error != null) _voiceError.value = result.error
            val text = result.partial.trim()
            _speechDraft.value = text
            _speechState.value = if (text.isNotBlank()) SpeechState.Draft else SpeechState.Idle
        }
    }

    /** Stops listening and keeps the transcript as a draft to accept or discard. */
    fun finishVoice() {
        if (!_voiceListening.value) return
        val text = speech.finish().trim()
        _voiceListening.value = false
        _speechDraft.value = text
        _speechState.value = if (text.isNotBlank()) SpeechState.Draft else SpeechState.Idle
    }

    /** Adds the dictation draft in front of whatever was already typed. */
    fun useSpeechDraft() {
        val text = _speechDraft.value?.trim().orEmpty()
        if (text.isNotBlank()) {
            val existing = conversation.value?.draft.orEmpty()
            draft(if (existing.isBlank()) text else existing.trimEnd() + " " + text)
        }
        _speechDraft.value = null
        _speechState.value = SpeechState.Idle
    }

    fun cancelSpeechDraft() {
        speech.cancel()
        voiceJob?.cancel(); voiceJob = null
        _voiceListening.value = false
        _speechDraft.value = null
        _speechState.value = SpeechState.Idle
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
    /** A redial or probe is in flight; the conversation page shows "Reconnecting". */
    private val _connecting = MutableStateFlow(false)
    val connecting: StateFlow<Boolean> = _connecting.asStateFlow()
    /** Per-Mac reachability, so one failed Mac is not hidden by another that answered. */
    private val _hostReachable = MutableStateFlow<Map<String, Boolean?>>(emptyMap())
    val hostReachable: StateFlow<Map<String, Boolean?>> = _hostReachable.asStateFlow()
    /** After repeated failures a Mac goes quiet: it keeps retrying without a red status. */
    private val hostFailures = mutableMapOf<String, Int>()
    private val quietHosts = mutableSetOf<String>()
    /** The Mac whose conversation is open; reads and writes must stay on it. */
    private var openHostID: String? = null
    /** When the app last went to the background, so a return redials every Mac. */
    private var backgroundedAt: Long? = null
    /** Feed replies currently in flight, so a second tap cannot duplicate one. */
    private val _feedBusy = MutableStateFlow(false)
    val feedBusy: StateFlow<Boolean> = _feedBusy.asStateFlow()
    /** A Feed read or reply failure; the Feed page shows it below its cards. */
    private val _feedError = MutableStateFlow<String?>(null)
    val feedError: StateFlow<String?> = _feedError.asStateFlow()
    private val _timingOpen = MutableStateFlow(false)
    val timingOpen: StateFlow<Boolean> = _timingOpen.asStateFlow()
    private val _connectionOpen = MutableStateFlow(false)
    val connectionOpen: StateFlow<Boolean> = _connectionOpen.asStateFlow()
    /** Which Mac the connection page describes; it may not be the open conversation's Mac. */
    private val _connectionHostID = MutableStateFlow<String?>(null)
    val connectionHostID: StateFlow<String?> = _connectionHostID.asStateFlow()
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

    /** The Mac the open conversation belongs to. */
    private fun openHost(): HostRuntime? =
        hosts.firstOrNull { it.id == openHostID } ?: hosts.firstOrNull { it.repository === repository }

    /** Whether the open conversation's Mac granted a capability. */
    fun allows(capability: com.cmuxremote.mobile.protocol.ClientCapability): Boolean =
        openHost()?.connection?.scope?.has(capability) == true

    /** The open conversation's Mac, for the page's subtitle. */
    fun openHostName(): String? = openHost()?.name

    /**
     * Probes the Mac again so the connection page can say whether it answers.
     * The probe is one signed read; it grants nothing.
     */
    private fun connectionHost(): HostRuntime? =
        hosts.firstOrNull { it.id == _connectionHostID.value }
            ?: hosts.firstOrNull { it.id == openHostID }
            ?: hosts.firstOrNull { it.repository === repository }
            ?: hosts.firstOrNull()

    fun refreshConnection() {
        val host = connectionHost()
        val current = host?.repository
        if (current == null || host == null) {
            _reachable.value = false
            _probed.value = true
            return
        }
        _connection.value = host.connection
        _connectionHostID.value = host.id
        _probed.value = false
        _connecting.value = true
        viewModelScope.launch {
            val reached = runCatching {
                kotlinx.coroutines.withTimeout(8_000) { current.probe() }
            }.isSuccess
            if (_connectionHostID.value == host.id) _reachable.value = reached
            _hostReachable.value = _hostReachable.value + (host.id to reached)
            _probed.value = true
            _connecting.value = false
        }
    }

    /** The status bar's retry: probe again, refresh the relay hint, then re-read the page. */
    fun retryConnection() {
        // A reader asking to retry brings a quiet Mac back into the status line.
        quietHosts.clear()
        hostFailures.clear()
        refreshConnection()
        viewModelScope.launch {
            repository?.let { refreshRelayHint(it) }
            if (_conversation.value != null) reloadOpen() else refresh()
        }
    }

    /** Whether reads are currently routed through the Mac's relay. */
    val overRelay: Boolean get() = repository?.overRelay == true

    fun openTiming() { _timingOpen.value = true }
    fun closeTiming() { _timingOpen.value = false }
    /** Opens one Mac's connection page; no argument means the currently selected one. */
    fun openConnection(hostID: String? = null) {
        // An explicit Mac wins; otherwise the open conversation's Mac, then the
        // last one whose page was shown.
        val host = (if (hostID != null) hosts.firstOrNull { it.id == hostID } else null)
            ?: hosts.firstOrNull { it.id == openHostID }
            ?: connectionHost()
        if (host != null) {
            _connectionHostID.value = host.id
            _connection.value = host.connection
        }
        _connectionOpen.value = true
    }

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
        lives.remove(id)?.stop()
        hosts.removeAll { it.id == id }
        _conversation.value = null
        openHostID = null
        if (hosts.isEmpty()) {
            com.cmuxremote.mobile.background.BackgroundSync.cancel(getApplication())
            repository = null
            _connection.value = null
            store.clear()
            _shell.value = ShellState.Pairing()
            return
        }
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

    fun setHostFilter(id: String?) {
        _hostFilter.value = id
        // "All Macs" is a clean slate, so a workspace from the previous Mac goes too.
        if (id == null) _workspaceFilter.value = null
    }

    fun setSidebar(open: Boolean) { _sidebarOpen.value = open }

    fun toggleCollapsed(key: String) {
        val next = _collapsed.value.toMutableSet().apply { if (!add(key)) remove(key) }
        _collapsed.value = next; prefs.edit().putString("collapsed", next.sorted().joinToString("\n")).apply()
    }
    /** Images prepared for the next send: file name to base64 payload. */
    private val _pendingImages = MutableStateFlow<List<Pair<String, String>>>(emptyList())
    val pendingImages: StateFlow<List<Pair<String, String>>> = _pendingImages.asStateFlow()
    /** Images being compressed; the composer says "Preparing image…" meanwhile. */
    private val _imagePreparing = MutableStateFlow(0)
    val imagePreparing: StateFlow<Int> = _imagePreparing.asStateFlow()
    private val _imageError = MutableStateFlow<String?>(null)
    val imageError: StateFlow<String?> = _imageError.asStateFlow()
    private val _task = MutableStateFlow<TaskUi?>(null)
    val task: StateFlow<TaskUi?> = _task.asStateFlow()
    private val _toolDetail = MutableStateFlow<ToolDetailUi?>(null)
    val toolDetail: StateFlow<ToolDetailUi?> = _toolDetail.asStateFlow()
    private val _start = MutableStateFlow<StartUi?>(null)
    val start: StateFlow<StartUi?> = _start.asStateFlow()

    /** One approved Mac and its own repository. */
    private class HostRuntime(var connection: AuthorizedConnection, var repository: BridgeRepository) {
        val id: String get() = connection.host.id
        val name: String get() = connection.host.name
    }

    /** Relay origins the reader added; kept across launches, never carrying a credential. */
    private val relayPrefs = application.getSharedPreferences("cmux-relay", android.content.Context.MODE_PRIVATE)
    private val _relayOrigins = MutableStateFlow(
        relayPrefs.getString("origins", "").orEmpty().split("\n").filter { it.isNotBlank() },
    )
    val relayOrigins: StateFlow<List<String>> = _relayOrigins.asStateFlow()
    private val _relayHosts = MutableStateFlow<List<EnrollmentBootstrap>>(emptyList())
    val relayHosts: StateFlow<List<EnrollmentBootstrap>> = _relayHosts.asStateFlow()
    private val _relayLoading = MutableStateFlow(false)
    val relayLoading: StateFlow<Boolean> = _relayLoading.asStateFlow()
    private val _relayError = MutableStateFlow<String?>(null)
    val relayError: StateFlow<String?> = _relayError.asStateFlow()

    /** The Macs advertising themselves on this network while a pairing page is open. */
    private val discovery = com.cmuxremote.mobile.bridge.BridgeDiscovery(application)
    private val _discovered = MutableStateFlow<List<com.cmuxremote.mobile.bridge.DiscoveredBridge>>(emptyList())
    val discovered: StateFlow<List<com.cmuxremote.mobile.bridge.DiscoveredBridge>> = _discovered.asStateFlow()

    fun startDiscovery() {
        discovery.start { values ->
            _discovered.value = values
            // A paired Mac that moved is reachable again at its advertised endpoint.
            relocateHosts(values)
        }
    }

    private fun relocateHosts(values: List<com.cmuxremote.mobile.bridge.DiscoveredBridge>) {
        values.forEach { bridge ->
            val host = hosts.firstOrNull { it.id == bridge.host.id } ?: return@forEach
            val endpoint = host.connection.endpoint
            if (endpoint.host == bridge.endpoint.host && endpoint.port == bridge.endpoint.port) return@forEach
            viewModelScope.launch {
                val updated = host.connection.copy(
                    endpoint = endpoint.copy(host = bridge.endpoint.host, port = bridge.endpoint.port),
                )
                val candidate = runCatching { BridgeRepository.open(updated) }.getOrNull() ?: return@launch
                // The advertised identity must still prove itself over the new endpoint.
                val reached = runCatching {
                    kotlinx.coroutines.withTimeout(8_000) { candidate.probe() }
                }.isSuccess
                if (!reached) return@launch
                host.connection = updated
                host.repository = candidate
                runCatching { store.saveToList(updated) }
                if (_connection.value?.host?.id == host.id) _connection.value = updated
                if (openHostID == host.id) {
                    repository = candidate
                    reloadOpen()
                }
                startLive(host)
                _hostReachable.value = _hostReachable.value + (host.id to true)
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                    "discovery",
                    "relocated ${host.name} to ${updated.endpoint.host}:${updated.endpoint.port}",
                )
            }
        }
    }

    fun stopDiscovery() {
        discovery.stop()
        _discovered.value = emptyList()
    }

    /** Macs already paired here, so a nearby list can mark them instead of offering them. */
    fun approvedHostIDs(): Set<String> = hosts.map { it.id }.toSet()

    /** Whether any paired Mac granted a read of its conversations. */
    fun canReadConversations(): Boolean = hosts.any {
        it.connection.scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationRead)
    }

    /** Adds one canonical relay origin and refreshes what it lists. */
    fun addRelayOrigin(text: String) {
        val canonical = try {
            com.cmuxremote.mobile.bridge.RelayEndpoint.canonicalOrigin(text.trim())
        } catch (error: ProtocolException) {
            _relayError.value = error.userMessage()
            return
        }
        if (_relayOrigins.value.contains(canonical)) {
            refreshRelayDirectory()
            return
        }
        if (_relayOrigins.value.size >= MAX_RELAY_ORIGINS) {
            _relayError.value = getApplication<Application>().getString(R.string.relay_limit)
            return
        }
        _relayOrigins.value = _relayOrigins.value + canonical
        saveRelayOrigins()
        refreshRelayDirectory()
    }

    fun removeRelayOrigin(origin: String) {
        _relayOrigins.value = _relayOrigins.value.filterNot { it == origin }
        _relayHosts.value = _relayHosts.value.filterNot { it.endpoint.relay?.origin == origin }
        saveRelayOrigins()
    }

    private fun saveRelayOrigins() {
        relayPrefs.edit().putString("origins", _relayOrigins.value.joinToString("\n")).apply()
    }

    private fun rememberRelayOrigin(origin: String?) {
        val value = origin?.takeIf { it.isNotBlank() } ?: return
        if (_relayOrigins.value.contains(value)) return
        _relayOrigins.value = _relayOrigins.value + value
        saveRelayOrigins()
    }

    /** Reads every saved relay's directory; each entry is verified before it is listed. */
    fun refreshRelayDirectory() {
        val origins = _relayOrigins.value
        if (origins.isEmpty()) {
            _relayHosts.value = emptyList()
            _relayError.value = null
            _relayLoading.value = false
            return
        }
        relayRefresh?.cancel()
        relayRefresh = viewModelScope.launch {
            _relayLoading.value = true
            _relayError.value = null
            var failure: String? = null
            val found = LinkedHashMap<String, EnrollmentBootstrap>()
            for (origin in origins) {
                val result = runCatching { com.cmuxremote.mobile.bridge.RelayDirectory.hosts(origin) }
                result.onFailure { failure = it.userMessage() }
                result.getOrDefault(emptyList()).forEach { entry ->
                    val existing = found[entry.host.id]
                    if (existing == null || existing.expiresAt <= entry.expiresAt) found[entry.host.id] = entry
                }
            }
            _relayHosts.value = found.values.sortedBy { it.host.name.lowercase() }
            _relayError.value = if (_relayHosts.value.isEmpty()) failure else null
            _relayLoading.value = false
        }
    }

    /**
     * Replaces this device's identity. A revoked identity can never join a relay
     * again (the relay keeps the revoked list), so re-pairing from outside the
     * LAN requires a new key. Every grant and local cache goes with the old one.
     */
    fun resetIdentity() {
        poll?.cancel(); poll = null
        approvalPoll?.cancel(); approvalPoll = null
        pollLoop?.cancel(); pollLoop = null
        liveRefresh?.cancel()
        backfill?.cancel()
        lives.values.forEach { it.stop() }
        lives.clear()
        openHostID = null
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { conversations.clearAll() }
            runCatching { taskCache.clearAll() }
        }
        store.clearIdentity()
        hosts.clear()
        repository = null
        _connection.value = null
        _conversation.value = null
        _selectedKey.value = null
        _models.value = emptyList()
        _pairing.value = null
        _addingDevice.value = false
        com.cmuxremote.mobile.background.BackgroundSync.cancel(getApplication())
        com.cmuxremote.mobile.data.Diagnostics.log(
            com.cmuxremote.mobile.data.Diagnostics.Level.Info,
            "identity",
            "device identity reset; pair again",
        )
        _shell.value = ShellState.Pairing()
    }

    /** Pairs with a Mac listed by one of the saved relays; the owner still approves it. */
    fun pairListed(bootstrap: EnrollmentBootstrap) {
        beginPairing {
            var enrollment = Enrollment.fromBootstrap(bootstrap, store.privateKey())
            val status = try {
                enrollment.submit()
            } catch (error: ProtocolException) {
                if (error.code != "invalid_enrollment") throw error
                enrollment.close()
                enrollment = Enrollment.fromBootstrap(
                    bootstrap,
                    store.privateKey(),
                    clientKind = "iphone",
                    capabilities = AndroidCapabilitiesBeforeStart,
                )
                enrollment.submit()
            }
            enrollment to status
        }
    }

    private val hosts = mutableListOf<HostRuntime>()
    private var repository: BridgeRepository? = null
    private var poll: Job? = null
    /** The request currently waiting for the owner, so Cancel reaches the Mac too. */
    private var pendingEnrollment: PendingEnrollment? = null
    /** The approval poll; paused in the background and resumed on return. */
    private var approvalPoll: Job? = null
    /** One encrypted link per Mac; a single link left every other Mac on slow polling. */
    private val lives = mutableMapOf<String, LiveUpdates>()
    private var networkCallback: android.net.ConnectivityManager.NetworkCallback? = null
    /** Debug-only: dial the relay even when the LAN answers, to test that path. */
    var forceRelay: Boolean = false
    private var liveRefresh: Job? = null
    private var pollLoop: Job? = null
    /** Fills the stored copy backwards while its page is open. */
    private var backfill: Job? = null
    /** The project page's current read; leaving the page cancels it. */
    private var projectJob: Job? = null
    /** Watches an open background task while it runs. */
    private var taskFollow: Job? = null
    /** Automatic earlier-page loads wait this long; a pull does not. */
    private var nextOlderAt = 0L
    private var relayRefresh: Job? = null
    /** A burst of live notifications writes the stored copy at most this often. */
    private val lastStoredAt = mutableMapOf<String, Long>()

    init {
        // A network that comes back needs a redial; the encrypted links do not
        // recover on their own when Wi-Fi returns or the phone switches to cellular.
        runCatching {
            val manager = application.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val callback = object : android.net.ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    if (hosts.isEmpty()) return
                    viewModelScope.launch { redialAll() }
                }
            }
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        }
        restore()
    }

    /** The app came back to the foreground: redial every Mac and re-read the open page. */
    fun onForeground() {
        val wasAway = backgroundedAt != null
        backgroundedAt = null
        if (hosts.isEmpty()) return
        startDiscovery()
        pendingEnrollment?.let { startApprovalPolling(it) }
        viewModelScope.launch {
            if (wasAway) redialAll()
            if (_conversation.value != null) {
                // A model list can change while the app is away.
                loadModels()
                reloadOpen()
            } else {
                refresh()
            }
        }
    }

    /** The app left the foreground: pause the slow poll until it returns. */
    fun onBackground() {
        backgroundedAt = System.currentTimeMillis()
        pollLoop?.cancel()
        pollLoop = null
        liveRefresh?.cancel()
        // A project read that outlives its page is wasted; the page reloads on return.
        projectJob?.cancel()
        discovery.stop()
        // The pass is scheduled when the app leaves, not only when it connected.
        if (_backgroundSync.value && hosts.isNotEmpty()) {
            com.cmuxremote.mobile.background.BackgroundSync.schedule(getApplication())
        }
    }

    private suspend fun redialAll() {
        _connecting.value = true
        // Each host keeps its own link and repository; a redial replaces only that link.
        hosts.forEach { host ->
            runCatching { refreshRelayHint(host.repository) }
            startLive(host)
        }
        _reachable.value = hosts.any { host -> runCatching { host.repository.epoch() }.isSuccess }
        _probed.value = true
        _connecting.value = false
        if (_conversation.value != null) reloadOpen() else refresh()
    }

    fun restore() {
        val saved = store.loadAll()
        if (saved.isEmpty()) {
            _shell.value = ShellState.Pairing()
            return
        }
        hosts.clear()
        saved.forEach { connection ->
            rememberRelayOrigin(connection.endpoint.relay?.origin)
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
        // Every saved Mac gets its own link; connect() handles the one being shown.
        hosts.filter { it.id != primary.id }.forEach { host ->
            if (!host.connection.isLegacy) startLive(host)
            viewModelScope.launch {
                if (host.connection.isLegacy) return@launch
                refreshRelayHint(host.repository)
                // A secondary Mac that is only reachable through its relay needs the
                // same link the primary gets, or it stays on slow HTTPS reads.
                if ((forceRelay || !lanReachable(host.repository, host.connection)) && host.connection.endpoint.relay != null) {
                    val relayed = dialRelay(host.connection, host.repository) ?: return@launch
                    host.repository.useRelayLink(relayed.link, relayed.epoch)
                    startLive(host, existing = relayed.link)
                }
            }
        }
        connect(primary.connection)
    }

    /** Pairs from a scanned or pasted v2 enrollment code, then waits for the owner. */
    fun pair(code: String) {
        // An old `cmux-remote://pair?v=1` code selects the legacy shared-token
        // connection explicitly; it is never reached from a v2 enrol link.
        LegacyPairingCodec.decode(code)?.let { legacy ->
            pairLegacy(legacy)
            return
        }
        beginPairing {
            var enrollment = Enrollment.begin(code, store.privateKey())
            val status = try {
                enrollment.submit()
            } catch (error: ProtocolException) {
                // A Bridge older than this client cannot decode the "android" kind and
                // closes the request; the iPhone kind means the same thing to it.
                if (error.code != "invalid_enrollment") throw error
                // Bridges before this client reject both the android kind and the
                // conversationStart capability; retry as the kind and scope they know.
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                    "enrollment",
                    "Bridge rejected the android request; retrying as iphone without conversationStart",
                )
                enrollment.close()
                enrollment = Enrollment.begin(
                    code,
                    store.privateKey(),
                    clientKind = "iphone",
                    capabilities = AndroidCapabilitiesBeforeStart,
                )
                enrollment.submit()
            }
            enrollment to status
        }
    }

    /**
     * Joins an explicitly chosen legacy shared-token Mac. This is the only path
     * that does not create a per-device grant; the reader must have enabled
     * `--legacy` on the Mac and accepts that authority is shared.
     */
    fun pairLegacy(pairing: LegacyPairing) {
        val checked = try {
            pairing.validate()
        } catch (error: ProtocolException) {
            publishPairing(ShellState.Pairing(error = error.userMessage()))
            return
        }
        if (hosts.size >= MAX_HOSTS) {
            publishPairing(
                ShellState.Failed("pairing_capacity", getApplication<Application>().getString(R.string.pair_capacity)),
            )
            return
        }
        publishPairing(ShellState.Pairing(busy = true))
        viewModelScope.launch {
            val connection = legacyConnection(checked)
            val repository = runCatching { BridgeRepository.open(connection) }.getOrElse { error ->
                publishPairing(ShellState.Pairing(error = error.userMessage()))
                return@launch
            }
            val answered = runCatching {
                kotlinx.coroutines.withTimeout(8_000) { repository.probe() }
            }.isSuccess
            if (!answered) {
                publishPairing(ShellState.Pairing(error = getApplication<Application>().getString(R.string.error_connection)))
                return@launch
            }
            store.saveToList(connection)
            if (hosts.none { it.id == connection.host.id }) hosts += HostRuntime(connection, repository)
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Warning,
                "enrollment",
                "legacy shared-token connection saved for ${checked.host}:${checked.port}",
            )
            _pairing.value = null
            _addingDevice.value = false
            connect(connection)
        }
    }

    /** A locally valid connection shell for a legacy shared token, never a v2 grant. */
    private fun legacyConnection(pairing: LegacyPairing): AuthorizedConnection {
        // The host identity is generated locally: a legacy Bridge proves itself by
        // the pinned certificate, not by a signed host key.
        val hostKey = Identity.generatePrivateKey()
        val hostPublicKey = Identity.publicKeyBase64(hostKey)
        val hostID = Identity.identityId(hostPublicKey)
        val deviceKey = store.privateKey()
        val clientID = Identity.identityId(Identity.publicKeyBase64(deviceKey))
        val scope = com.cmuxremote.mobile.protocol.ClientScope(
            workspaces = emptyList(),
            capabilities = com.cmuxremote.mobile.protocol.ClientCapability.entries.toList(),
        )
        val grant = com.cmuxremote.mobile.protocol.EnrollmentGrant(
            hostID = hostID,
            clientID = clientID,
            requestID = java.util.UUID.randomUUID().toString(),
            nonce = java.util.UUID.randomUUID().toString(),
            scope = scope,
            issuedAt = System.currentTimeMillis() / 1000,
        )
        val signature = Identity.base64(
            Identity.sign(
                com.cmuxremote.mobile.protocol.signedBytes("grant", grant.toJson()),
                hostKey,
            ),
        )
        return AuthorizedConnection(
            host = com.cmuxremote.mobile.protocol.HostIdentity(
                id = hostID,
                publicKey = hostPublicKey,
                certificateSHA256 = pairing.certificateSHA256,
                name = pairing.host,
            ),
            endpoint = com.cmuxremote.mobile.protocol.BridgeEndpoint(pairing.host, pairing.port),
            privateKey = deviceKey,
            clientID = clientID,
            scope = scope,
            grantSignature = signature,
            grant = grant,
            legacyToken = pairing.token,
        ).also { it.validate() }
    }

    /** Pairs with a Mac found on the local network; the owner still has to approve it. */
    fun pairDiscovered(bridge: com.cmuxremote.mobile.bridge.DiscoveredBridge) {
        beginPairing {
            var enrollment = Enrollment.beginDiscovered(bridge.endpoint, bridge.host, store.privateKey())
            val status = try {
                enrollment.submit()
            } catch (error: ProtocolException) {
                if (error.code != "invalid_enrollment") throw error
                enrollment.close()
                enrollment = Enrollment.beginDiscovered(
                    bridge.endpoint,
                    bridge.host,
                    store.privateKey(),
                    clientKind = "iphone",
                    capabilities = AndroidCapabilitiesBeforeStart,
                )
                enrollment.submit()
            }
            enrollment to status
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
                pendingEnrollment = enrollment
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
                        clientID = enrollment.request.clientID,
                    ),
                )
                startApprovalPolling(enrollment)
            } catch (error: ProtocolException) {
                pendingEnrollment = null
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: "Pairing failed."))
                pending?.cancel()
            } catch (error: Exception) {
                pendingEnrollment = null
                // A pairing failure is worth one line: the code, never the key or the request body.
                android.util.Log.w("cmux-pair", "pairing failed: " + error.javaClass.name + " " + (error.message ?: ""))
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: getApplication<Application>().getString(R.string.error_pairing_failed)))
                pending?.cancel()
            }
        }
    }

    /** Watches the request until the owner answers; suspended while the app is away. */
    private fun startApprovalPolling(enrollment: PendingEnrollment) {
        approvalPoll?.cancel()
        approvalPoll = viewModelScope.launch {
            var transientFailures = 0
            try {
                repeat(150) {
                    if (!isActive) return@launch
                    delay(2_000)
                    // A lost poll is not a denied request: retry transiently for the
                    // life of the window instead of ending a pairing the owner may
                    // still be approving.
                    val status = try {
                        enrollment.status()
                    } catch (error: ProtocolException) {
                        if (transientEnrollment(error) && transientFailures < 8) {
                            transientFailures += 1
                            return@repeat
                        }
                        throw error
                    } catch (error: Exception) {
                        if (transientFailures < 8) {
                            transientFailures += 1
                            return@repeat
                        }
                        throw error
                    }
                    transientFailures = 0
                    if (status.state == "approved") {
                        finish(enrollment, status)
                        return@launch
                    }
                    if (status.state == "denied" || status.state == "cancelled" ||
                        status.state == "expired" || status.state == "revoked"
                    ) {
                        pendingEnrollment = null
                        publishPairing(
                            ShellState.Failed(
                                "enrollment_" + status.state,
                                getApplication<Application>().getString(R.string.pair_enrollment_ended),
                            ),
                        )
                        return@launch
                    }
                }
                pendingEnrollment = null
                publishPairing(
                    ShellState.Failed(
                        "enrollment_expired",
                        getApplication<Application>().getString(R.string.pair_enrollment_window_closed),
                    ),
                )
            } catch (error: ProtocolException) {
                pendingEnrollment = null
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: "Pairing failed."))
                runCatching { enrollment.cancel() }
            } catch (error: Exception) {
                pendingEnrollment = null
                android.util.Log.w("cmux-pair", "pairing poll failed: " + error.javaClass.name + " " + (error.message ?: ""))
                publishPairing(ShellState.Pairing(error = error.userMessage() ?: getApplication<Application>().getString(R.string.error_pairing_failed)))
                runCatching { enrollment.cancel() }
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
        val request = pendingEnrollment
        pendingEnrollment = null
        // Tell the Mac the request is withdrawn; the owner should not see it linger.
        request?.let { enrollment -> viewModelScope.launch { enrollment.cancel() } }
        poll?.cancel()
        approvalPoll?.cancel()
        approvalPoll = null
        if (_pairing.value != null) {
            _pairing.value = null
            _addingDevice.value = false
        } else {
            _shell.value = ShellState.Pairing()
        }
    }

    /** A poll failure the next poll may recover from. */
    private fun transientEnrollment(error: ProtocolException): Boolean =
        error.code in setOf("connection_failed", "link_failed", "timeout", "relay_unavailable", "invalid_proof", "replayed_request")

    private suspend fun finish(enrollment: PendingEnrollment, status: EnrollmentStatus) {
        pendingEnrollment = null
        // The iPhone caps approved Macs at 16; a request beyond that is refused
        // instead of quietly growing an unbounded list.
        if (hosts.size >= MAX_HOSTS && hosts.none { it.id == enrollment.bootstrap.host.id }) {
            enrollment.close()
            publishPairing(
                ShellState.Failed(
                    "pairing_capacity",
                    getApplication<Application>().getString(R.string.pair_capacity),
                ),
            )
            return
        }
        val grant = enrollment.grant(status)
        // The enrollment window's relay permit is not valid for an approved device.
        // The Bridge returns a permit bound to this client key in the status; keep that
        // one, or none, when saving the connection.
        val approvedRelay = status.relay?.also { relay ->
            relay.validate(enrollment.bootstrap.host.id, Identity.publicKeyBase64(store.privateKey()))
            relay.verify(enrollment.bootstrap.host.publicKey)
        }
        val connection = AuthorizedConnection(
            host = enrollment.bootstrap.host,
            endpoint = enrollment.bootstrap.endpoint.copy(relay = approvedRelay),
            privateKey = store.privateKey(),
            clientID = enrollment.request.clientID,
            scope = grant.scope,
            grantSignature = status.grantSignature ?: "",
            grant = grant,
        )
        connection.validate()
        // Do not install a grant the Mac does not answer on: the owner may have
        // approved a Mac whose address this phone cannot reach.
        val answered = runCatching {
            kotlinx.coroutines.withTimeout(8_000) { BridgeRepository.open(connection).probe() }
        }.isSuccess
        if (!answered) {
            enrollment.close()
            publishPairing(
                ShellState.Pairing(error = getApplication<Application>().getString(R.string.error_connection)),
            )
            return
        }
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
        rememberRelayOrigin(connection.endpoint.relay?.origin)
        // The enrollment link used the window's permit; the connection opens its own.
        enrollment.close()
        _pairing.value = null
        _addingDevice.value = false
        connect(connection)
    }

    private fun connect(connection: AuthorizedConnection) {
        rememberRelayOrigin(connection.endpoint.relay?.origin)
        _connection.value = connection
        _reachable.value = true
        _probed.value = true
        _canStart.value = connection.scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationStart)
        if (_backgroundSync.value) com.cmuxremote.mobile.background.BackgroundSync.schedule(getApplication())
        // Reuse the host's repository: a second instance would keep the relay link
        // while the list refreshed through the old, LAN-only one.
        val existingHost = hosts.firstOrNull { it.id == connection.host.id }
        val repository = existingHost?.repository ?: BridgeRepository.open(connection).also {
            hosts += HostRuntime(connection, it)
        }
        existingHost?.connection = connection
        this.repository = repository
        val host = hosts.first { it.id == connection.host.id }
        // Show the last background snapshot immediately; the live read replaces it.
        _shell.value = cachedState() ?: ShellState.Connected(connection.host.name, emptyList(), loading = true)
        // A legacy shared-token connection has no signed link or relay permit.
        if (!connection.isLegacy) startLive(host)
        viewModelScope.launch {
            // The LAN probe and the relay dial start together; a Mac that is only
            // reachable through its relay no longer waits out the LAN timeout.
            val relay = if (connection.isLegacy) null else connection.endpoint.relay
            if (relay != null) {
                if (forceRelay) {
                    val relayed = dialRelay(connection, repository)
                    if (relayed != null) {
                        repository.useRelayLink(relayed.link, relayed.epoch)
                        startLive(host, existing = relayed.link)
                    }
                } else {
                    kotlinx.coroutines.coroutineScope {
                        val lan = async { lanReachable(repository, connection) }
                        val relayed = async { dialRelay(connection, repository) }
                        val lanWon = lan.await()
                        val relayResult = relayed.await()
                        if (lanWon) {
                            // The LAN answered; a relay link that also opened is closed.
                            runCatching { relayResult?.link?.close() }
                        } else if (relayResult != null) {
                            repository.useRelayLink(relayResult.link, relayResult.epoch)
                            startLive(host, existing = relayResult.link)
                        }
                    }
                }
            }
            // Over whichever transport answered, learn the current approved relay
            // permit so a rotated relay needs no new pairing.
            refreshRelayHint(repository)
            refresh()
        }
    }

    /**
     * Replaces the saved relay permit with the host's current signed hint.
     * Failure is routine (an old Bridge, or a stale permit with no reachable
     * transport) and must not disturb the read that follows.
     */
    private suspend fun refreshRelayHint(repository: BridgeRepository) {
        if (repository.connection.isLegacy) return
        val hint = runCatching { repository.relayHint() }.getOrElse { error ->
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Debug,
                "relay",
                "relay hint unavailable: ${(error as? ProtocolException)?.code ?: error.javaClass.simpleName}",
            )
            return
        }
        val host = hosts.firstOrNull { it.repository === repository } ?: return
        val relay = hint.relay
        relay?.let { endpoint ->
            endpoint.validate(host.connection.host.id, Identity.publicKeyBase64(host.connection.privateKey))
            endpoint.verify(host.connection.host.publicKey)
        }
        if (host.connection.endpoint.relay?.admission == relay?.admission &&
            host.connection.endpoint.relay?.origin == relay?.origin
        ) {
            return
        }
        val updated = host.connection.copy(
            endpoint = host.connection.endpoint.copy(relay = relay),
        )
        host.connection = updated
        runCatching { store.saveToList(updated) }
        if (_connection.value?.host?.id == updated.host.id) _connection.value = updated
        rememberRelayOrigin(relay?.origin)
        com.cmuxremote.mobile.data.Diagnostics.log(
            com.cmuxremote.mobile.data.Diagnostics.Level.Info,
            "relay",
            "approved relay permit refreshed from ${relay?.origin ?: "LAN only"}",
        )
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

    private class Relayed(
        val link: com.cmuxremote.mobile.bridge.LinkClient,
        val epoch: String,
    )

    /** Dials the host's relay and returns the authenticated link, or null. */
    private suspend fun dialRelay(connection: AuthorizedConnection, repository: BridgeRepository): Relayed? {
        val relay = connection.endpoint.relay ?: return null
        val link = com.cmuxremote.mobile.bridge.LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = com.cmuxremote.mobile.protocol.HpkeSession.generateKeyPair(),
            onEvent = { event -> onLiveChange(connection.host.id, event.id) },
        )
        return try {
            android.util.Log.i("cmux-relay", "dial relay ${relay.origin}")
            link.connectForcedRelay(relay)
            android.util.Log.i("cmux-relay", "relay connected open=${link.isOpen} relayed=${link.dialedViaRelay}")
            // The epoch must be read *over this link*: the LAN is the unreachable path,
            // so a normal signed HTTPS read would time out and leave the link unused.
            val body = link.request("GET", "/v2/identity", null, null)
            val signed = com.cmuxremote.mobile.protocol.decodeSignedJson(String(body, Charsets.UTF_8))
            com.cmuxremote.mobile.protocol.Signer.verify(signed, "host", connection.host.publicKey)
            val announcement = com.cmuxremote.mobile.protocol.HostAnnouncement.from(
                signed.value as? kotlinx.serialization.json.JsonObject
                    ?: throw ProtocolException("invalid_response", "The identity is not an object."),
            )
            if (announcement.host.id != connection.host.id || announcement.epoch.isBlank()) {
                throw ProtocolException("host_changed", "The relay link answered for another host.")
            }
            link.epoch = announcement.epoch
            android.util.Log.i("cmux-relay", "relay epoch read ${announcement.epoch}")
            Relayed(link, announcement.epoch)
        } catch (error: Exception) {
            android.util.Log.w("cmux-relay", "relay dial failed: ${error.javaClass.name} ${(error as? ProtocolException)?.code ?: error.message}")
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Warning,
                "relay",
                "relay dial failed: ${(error as? ProtocolException)?.code ?: error.javaClass.simpleName}",
            )
            runCatching { link.close() }
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
    private fun startLive(host: HostRuntime, existing: com.cmuxremote.mobile.bridge.LinkClient? = null) {
        lives.remove(host.id)?.stop()
        val updates = LiveUpdates(
            host.connection,
            viewModelScope,
            { path -> onLiveChange(host.id, path) },
            { host.repository.epoch() },
            existing = existing,
        )
        lives[host.id] = updates
        updates.start()
        updates.watch(listPaths())
    }

    /** Resources watched while the list is on screen. */
    private fun listPaths(): List<String> = listOf("/v2/sessions", "/v2/feed")

    private fun onLiveChange(hostID: String, path: String) {
        // Coalesce bursts: a running turn fires several notifications per second.
        liveRefresh?.cancel()
        liveRefresh = viewModelScope.launch {
            kotlinx.coroutines.delay(250)
            if (path.startsWith("/v2/sessions/") && path.endsWith("/history")) {
                // Only the open conversation's own Mac changes what its page shows.
                if (openHostID == hostID) reloadOpen()
            } else {
                refresh()
                if (openHostID == hostID) reloadOpen()
            }
        }
    }

    private fun watchOpenSession(sessionID: String?) {
        pollLoop?.cancel()
        val paths = buildList {
            addAll(listPaths())
            if (sessionID != null) add("/v2/sessions/$sessionID/history")
        }
        lives.values.forEach { it.watch(paths) }
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
                        val scope = host.connection.scope
                        val canRead = scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationRead)
                        val canWorkspace = scope.has(com.cmuxremote.mobile.protocol.ClientCapability.WorkspaceRead)
                        val canFeed = scope.has(com.cmuxremote.mobile.protocol.ClientCapability.FeedRead)
                        // An empty session list is a normal state, not a failed read.
                        // A Mac without conversationRead is not asked at all; its last
                        // known list is kept rather than being replaced with "empty".
                        val read: Result<List<SessionDescriptor>> = if (canRead) {
                            runCatching { host.repository.sessions() }
                        } else {
                            Result.success(previousByHost[host.id].orEmpty())
                        }
                        val workList = if (canWorkspace) {
                            runCatching { host.repository.workspaces().toMap() }.getOrDefault(emptyMap())
                        } else {
                            emptyMap()
                        }
                        val feedRead = if (canFeed) runCatching { host.repository.feed() } else Result.success(emptyList())
                        val feedItems = feedRead.getOrDefault(emptyList())
                        val stored = if (read.isFailure) cache.load(host.id) else null
                        val cached = stored?.let { BridgeRepository.decodeSessions(it.sessionsJson) }.orEmpty()
                        val sessions = read.getOrNull()
                            ?: cached.ifEmpty { previousByHost[host.id].orEmpty() }
                        val pendingCount = feedItems.count { it.status == "pending" }
                        if (read.isSuccess && canRead) {
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
                            workspaces = workList,
                            // A Feed reply goes back to the Mac that reported the event.
                            feed = feedItems.map { it.copy(hostID = host.id, hostName = host.name) },
                            reached = read.isSuccess,
                            cachedPending = if (read.isSuccess) 0 else stored?.pendingCount ?: 0,
                            feedError = feedRead.exceptionOrNull()?.let { error ->
                                (error as? ProtocolException)?.userMessage() ?: error.message
                            },
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
            results.forEach { read ->
                if (read.reached) {
                    hostFailures.remove(read.host.id)
                    quietHosts.remove(read.host.id)
                } else {
                    val failures = (hostFailures[read.host.id] ?: 0) + 1
                    hostFailures[read.host.id] = failures
                    if (failures >= 3) quietHosts.add(read.host.id)
                }
            }
            _hostReachable.value = results.associate {
                it.host.id to if (it.host.id in quietHosts) null else it.reached
            }
            _feedError.value = results.firstNotNullOfOrNull { it.feedError }
            // A filter naming a Mac or workspace that no longer exists would hide
            // the whole list with no way to tell why.
            _hostFilter.value?.let { id -> if (hosts.none { it.id == id }) _hostFilter.value = null }
            _workspaceFilter.value?.let { id ->
                if (workspaces.keys.none { it.equals(id, ignoreCase = true) }) _workspaceFilter.value = null
            }
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
        val feedError: String? = null,
    )

    fun open(hosted: HostedSession) {
        val host = hosts.firstOrNull { it.id == hosted.hostID } ?: return
        repository = host.repository
        openHostID = host.id
        _selectedKey.value = hosted.hostID + ":" + hosted.session.id
        // A secondary Mac only reaches its own transport now; refresh its permit too.
        viewModelScope.launch { refreshRelayHint(host.repository) }
        open(hosted.session)
    }

    fun open(session: SessionDescriptor) {
        val current = repository ?: return
        backfill?.cancel()
        // Selection is host-qualified: two Macs may report the same session id.
        val host = hosts.firstOrNull { it.repository === current }
        openHostID = host?.id
        _selectedKey.value = host?.let { it.id + ":" + session.id }
        watchOpenSession(session.id)
        val scope = storeScope(current.connection)
        // An unknown-outcome send belongs to one host and one conversation.
        _pendingOperation.value = prefs.getString(pendingKey(scope, session.id), null)
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
                val feed = runCatching { current.feed() }.getOrDefault(emptyList()).map {
                    it.copy(hostID = host?.id.orEmpty(), hostName = host?.name.orEmpty())
                }
                _conversation.update { ui ->
                    if (ui?.session?.id != session.id) ui
                    else applySnapshot(ui, snapshot, ui.session, feed).copy(
                        preview = preview?.text,
                        compacting = preview?.compacting ?: false,
                        loading = false,
                    )
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
                // A lost link is the status bar's story; only an application refusal
                // belongs in the transcript.
                val message = if (isConnectivity(error)) null else error.userMessage()
                _conversation.update { it?.copy(loading = false, error = message) }
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

    /** Codes the connection bar owns; they resolve on the next redial without user action. */
    private fun isConnectivity(error: ProtocolException): Boolean =
        error.code in setOf(
            "connection_failed", "link_failed", "timeout", "relay_unavailable",
            "bridge_offline", "bridge_starting", "bridge_replaced", "invalid_proof",
            "replayed_request", "relay_configuration",
        )

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
            clipped = snapshot.clipped,
            generation = snapshot.generation,
            turnStartedAt = if (session.working) snapshot.currentTurnStartedAt else null,
            compacting = if (session.working) ui.compacting else false,
            // The acknowledgement is only about the turn that is now over.
            stopRequested = ui.stopRequested && session.working,
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
        openHostID = null
        _pendingOperation.value = null
        watchOpenSession(null)
    }

    fun openFeed() = openFeed(hostID = null)

    fun openFeed(hostID: String?) {
        _feedHost.value = hostID
        _feedOpen.value = true
    }

    fun closeFeed() {
        _feedOpen.value = false
        _feedHost.value = null
    }

    fun openProject() = openProjectAt(null)

    /** Opens the project page at a file a tool referenced, or at its first change. */
    fun openProjectAt(path: String?) {
        val conversation = _conversation.value ?: return
        _project.value = ProjectUi(inputPath = path.orEmpty())
        projectJob?.cancel()
        projectJob = viewModelScope.launch {
            try {
                val current = openHost()?.repository ?: repository ?: return@launch
                val changes = current.project().changes(conversation.session.id)
                _project.update { it?.copy(changes = changes, loading = false) }
                // A tool reference opens that file; otherwise the page starts on changes.
                if (path.isNullOrBlank()) {
                    _project.update { it?.copy(mode = "changes", loading = false) }
                } else {
                    loadProjectFile(path)
                }
            } catch (error: ProtocolException) {
                _project.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    fun closeProject() {
        projectJob?.cancel()
        projectJob = null
        _project.value = null
    }

    fun setProjectPath(text: String) {
        _project.update { it?.copy(inputPath = text) }
    }

    /** Reads any relative path the reader typed. */
    fun openProjectPathInput() {
        val path = _project.value?.inputPath?.trim().orEmpty()
        if (path.isEmpty()) {
            showProjectChanges()
        } else {
            loadProjectFile(path)
        }
    }

    /** The whole working tree's diff, without a path scoping it. */
    fun showProjectDiff() {
        _project.update { it?.copy(mode = "diff", selectedPath = null, text = null, loading = true, error = null) }
        readProject("diff", "")
    }

    fun showProjectChanges() {
        projectJob?.cancel()
        _project.update { it?.copy(mode = "changes", selectedPath = null, text = null, loading = false, error = null) }
    }

    /** A changed file: a deletion is shown as its diff, everything else as its text. */
    fun selectChange(path: String) {
        val change = _project.value?.changes?.firstOrNull { it.path == path }
        if (change != null && change.status.trim().startsWith("D")) {
            _project.update { it?.copy(mode = "diff", selectedPath = path, inputPath = path, loading = true, error = null) }
            readProject("diff", path)
        } else {
            loadProjectFile(path)
        }
    }

    fun refreshProject() {
        val project = _project.value ?: return
        when (project.mode) {
            "changes" -> {
                val conversation = _conversation.value ?: return
                projectJob?.cancel()
                projectJob = viewModelScope.launch {
                    try {
                        val current = openHost()?.repository ?: repository ?: return@launch
                        val changes = current.project().changes(conversation.session.id)
                        _project.update { it?.copy(changes = changes, loading = false, error = null) }
                    } catch (error: ProtocolException) {
                        _project.update { it?.copy(loading = false, error = error.userMessage()) }
                    }
                }
            }
            "diff" -> readProject("diff", project.selectedPath.orEmpty())
            else -> project.selectedPath?.let(::loadProjectFile)
        }
    }

    private fun loadProjectFile(path: String) {
        _project.update { it?.copy(mode = "file", selectedPath = path, inputPath = path, text = null, loading = true, error = null) }
        readProject("file", path)
    }

    private fun readProject(resource: String, path: String) {
        val conversation = _conversation.value ?: return
        projectJob?.cancel()
        projectJob = viewModelScope.launch {
            try {
                val current = openHost()?.repository ?: repository ?: return@launch
                val reader = current.project()
                val text = if (resource == "diff") reader.diff(conversation.session.id, path) else reader.file(conversation.session.id, path)
                _project.update { it?.copy(text = text, loading = false, error = null) }
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

    /** Opens an activity group whose inline card only shows its newest slice. */
    fun openGroup(messages: List<ChatMessage>) {
        _group.value = GroupUi(messages)
    }

    fun closeGroup() {
        _group.value = null
    }

    fun openTask(info: com.cmuxremote.mobile.data.BackgroundTaskInfo) {
        taskFollow?.cancel()
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
                    else ui.copy(
                        text = page.text,
                        loading = false,
                        nextOffset = page.nextOffset,
                        messages = page.messages,
                        command = page.command ?: ui.command,
                        totalBytes = page.totalBytes ?: ui.totalBytes,
                        running = page.running ?: info.running,
                    )
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
                if (page.running == true) startTaskFollow(current, scope, sessionID, info.id)
            } catch (error: ProtocolException) {
                _task.update { it?.copy(loading = false, error = error.userMessage()) }
            }
        }
    }

    /** While a task runs and its sheet is open, read what it added. */
    private fun startTaskFollow(current: BridgeRepository, scope: String, sessionID: String, taskID: String) {
        taskFollow?.cancel()
        taskFollow = viewModelScope.launch {
            while (isActive) {
                delay(2_000)
                val ui = _task.value ?: return@launch
                if (ui.task.id != taskID || !ui.running) return@launch
                val page = runCatching { current.task(sessionID, taskID) }.getOrNull() ?: continue
                _task.update {
                    it?.copy(
                        text = if (page.kind == "agent" || page.messages.isNotEmpty()) page.text else page.text,
                        messages = if (page.messages.isNotEmpty()) page.messages else it.messages,
                        command = page.command ?: it.command,
                        nextOffset = page.nextOffset,
                        totalBytes = page.totalBytes ?: it.totalBytes,
                        running = page.running ?: it.running,
                    )
                }
                withContext(Dispatchers.IO) {
                    runCatching {
                        taskCache.save(
                            BackgroundTaskCache.Entry(
                                tool = ui.task.tool,
                                summary = ui.task.summary,
                                running = page.running ?: ui.running,
                                text = page.text,
                                nextOffset = page.nextOffset,
                                storedAt = System.currentTimeMillis(),
                            ),
                            scope,
                            sessionID,
                            taskID,
                        )
                    }
                }
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
                        messages = if (page.messages.isEmpty()) it.messages else it.messages + page.messages,
                        running = page.running ?: it.running,
                        totalBytes = page.totalBytes ?: it.totalBytes,
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
        taskFollow?.cancel()
        taskFollow = null
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
                val message = when (error.code) {
                    "stale_detail" -> getApplication<Application>().getString(R.string.tool_detail_stale)
                    "not_found" -> getApplication<Application>().getString(R.string.tool_detail_missing)
                    else -> error.userMessage()
                }
                _toolDetail.update { it?.copy(loading = false, error = message) }
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
        _start.value = StartUi(busy = true)
        viewModelScope.launch {
            // Every Mac that granted conversationStart may start a conversation;
            // the workspace row names its Mac and the start goes back to it.
            val targets = hosts.filter {
                it.connection.scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationStart)
            }.ifEmpty { hosts }
            val collected = kotlinx.coroutines.coroutineScope {
                targets.map { host ->
                    async(Dispatchers.IO) {
                        runCatching {
                            host.repository.workspaces().map { (id, title) ->
                                StartWorkspace(id, title, host.id, host.name)
                            }
                        }.getOrDefault(emptyList()) to host
                    }
                }.awaitAll()
            }
            val workspaces = collected.flatMap { it.first }
            val failures = collected.mapNotNull { (list, host) ->
                if (list.isEmpty() && targets.size == 1) host.name else null
            }
            _start.update {
                it?.copy(
                    workspaces = workspaces,
                    busy = false,
                    error = if (workspaces.isEmpty() && failures.isNotEmpty()) {
                        getApplication<Application>().getString(R.string.error_connection)
                    } else {
                        null
                    },
                )
            }
            val preferred = workspaces.firstOrNull { it.id == workspaceID } ?: workspaces.firstOrNull()
            preferred?.let { pickStartWorkspace(it) }
        }
    }

    fun closeStart() {
        _start.value = null
    }

    fun pickStartWorkspace(workspace: StartWorkspace) {
        val host = startHost(workspace) ?: return
        _start.update {
            it?.copy(
                selectedWorkspace = workspace,
                roots = emptyList(),
                selectedRoot = null,
                path = "",
                folders = emptyList(),
                foldersError = null,
                busy = true,
                error = null,
                notice = null,
            )
        }
        viewModelScope.launch {
            try {
                val roots = host.repository.startRoots(workspace.id).map { (id, path) -> StartRoot(id, path) }
                _start.update { it?.copy(roots = roots, selectedRoot = roots.firstOrNull(), busy = false) }
                roots.firstOrNull()?.let { selectStartPath("") }
            } catch (error: ProtocolException) {
                _start.update {
                    it?.copy(
                        busy = false,
                        error = error.userMessage(),
                        notice = getApplication<Application>().getString(R.string.start_no_directories),
                    )
                }
            }
        }
    }

    /** Reloads the roots of the selected workspace; the iOS page offers a pull. */
    fun refreshStartRoots() {
        val state = _start.value ?: return
        val workspace = state.selectedWorkspace ?: return
        pickStartWorkspace(workspace)
    }

    fun pickStartRoot(root: StartRoot) {
        _start.update { it?.copy(selectedRoot = root) }
        selectStartPath("")
    }

    /** Opens a subfolder of the selected root; the path is relative to the root. */
    fun openStartFolder(name: String) {
        val state = _start.value ?: return
        val next = if (state.path.isBlank()) name else state.path + "/" + name
        selectStartPath(next)
    }

    /** Steps back one folder, stopping at the root. */
    fun upStartFolder() {
        val state = _start.value ?: return
        val parent = state.path.substringBeforeLast('/', "")
        selectStartPath(parent)
    }

    private fun selectStartPath(path: String) {
        val state = _start.value ?: return
        val workspace = state.selectedWorkspace ?: return
        val root = state.selectedRoot ?: return
        val host = startHost(workspace) ?: return
        _start.update {
            it?.copy(path = path, folders = emptyList(), foldersLoading = true, foldersError = null)
        }
        viewModelScope.launch {
            try {
                val listing = host.repository.startFolders(workspace.id, root.id, path)
                _start.update {
                    it?.copy(
                        folders = listing.directories,
                        foldersTruncated = listing.truncated,
                        foldersLoading = false,
                    )
                }
            } catch (error: ProtocolException) {
                _start.update { it?.copy(foldersLoading = false, foldersError = error.userMessage()) }
            }
        }
    }

    fun pickStartAgent(agent: String) = _start.update { it?.copy(agent = agent, operation = null, uncertain = false) }

    fun startPrompt(text: String) = _start.update { it?.copy(prompt = text) }

    private fun startHost(workspace: StartWorkspace): HostRuntime? =
        hosts.firstOrNull { it.id == workspace.hostID }
            ?: hosts.firstOrNull { it.repository === repository }

    /** Opens a terminal running the fixed agent command; the phone never chooses a command. */
    fun startSession() = startSession(fresh = false)

    /** Deliberately opens another terminal after an unknown outcome. */
    fun startSessionFresh() = startSession(fresh = true)

    private fun startSession(fresh: Boolean) {
        val state = _start.value ?: return
        val workspace = state.selectedWorkspace ?: return
        val root = state.selectedRoot ?: return
        val host = startHost(workspace) ?: return
        if (state.busy) return
        val known = (_shell.value as? ShellState.Connected)?.sessions
            ?.filter { it.hostID == host.id }
            ?.map { it.session.id }?.toSet() ?: emptySet()
        // Repeating an unknown start reuses its operation identity, so the Mac
        // answers instead of opening a second terminal; a fresh start is explicit.
        val operation = state.operation?.takeIf { !fresh && state.uncertain }
            ?: java.util.UUID.randomUUID().toString()
        _start.update { it?.copy(busy = true, error = null, notice = null, operation = operation) }
        viewModelScope.launch {
            try {
                val receipt = host.repository.startSession(
                    workspace.id,
                    root.id,
                    state.path,
                    state.agent,
                    state.prompt.ifBlank { null },
                    operation,
                )
                val object_ = receipt as? kotlinx.serialization.json.JsonObject
                val accepted = object_?.let { it["accepted"]?.toString()?.trim('"') != "false" } ?: true
                val surface = object_?.get("surface_id")?.toString()?.trim('"')
                if (!accepted && surface.isNullOrBlank()) {
                    _start.update {
                        it?.copy(
                            busy = false,
                            uncertain = true,
                            error = getApplication<Application>().getString(R.string.start_outcome_unknown),
                        )
                    }
                    return@launch
                }
                _start.update {
                    it?.copy(
                        busy = false,
                        operation = null,
                        uncertain = false,
                        prompt = "",
                        notice = getApplication<Application>().getString(R.string.start_waiting),
                    )
                }
                repeat(20) {
                    delay(1500)
                    refresh()
                    val sessions = (_shell.value as? ShellState.Connected)?.sessions ?: return@repeat
                    // Only a conversation that did not exist before this start counts.
                    val match = sessions.firstOrNull { hosted ->
                        val session = hosted.session
                        hosted.hostID == host.id &&
                            session.id !in known &&
                            session.workspaceID?.lowercase() == workspace.id.lowercase() &&
                            (surface.isNullOrBlank() || session.surfaceID?.lowercase() == surface.lowercase())
                    }
                    if (match != null) {
                        _start.value = null
                        open(match)
                        return@launch
                    }
                }
                _start.update {
                    it?.copy(notice = getApplication<Application>().getString(R.string.start_not_seen))
                }
            } catch (error: ProtocolException) {
                val uncertain = error.code == "outcome_unknown"
                val message = when (error.code) {
                    "outcome_unknown" -> getApplication<Application>().getString(R.string.start_outcome_unknown)
                    "stale_binding" -> getApplication<Application>().getString(R.string.start_folder_gone)
                    else -> error.userMessage()
                }
                _start.update { it?.copy(busy = false, uncertain = uncertain, error = message) }
            } catch (error: Exception) {
                _start.update {
                    it?.copy(
                        busy = false,
                        uncertain = true,
                        error = error.userMessage() ?: getApplication<Application>().getString(R.string.start_outcome_unknown),
                    )
                }
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

    fun beginImagePreparation() {
        _imageError.value = null
        _imagePreparing.value += 1
    }

    fun endImagePreparation(error: String? = null) {
        _imagePreparing.value = (_imagePreparing.value - 1).coerceAtLeast(0)
        if (error != null) _imageError.value = error
    }

    fun attachImage(fileName: String, base64: String) {
        if (_pendingImages.value.size >= 4) {
            _imageError.value = getApplication<Application>().getString(R.string.chat_images_limit)
            return
        }
        _pendingImages.update { it + (fileName to base64) }
    }

    fun clearImageError() { _imageError.value = null }

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
        val scope = storeScope(current.connection)
        viewModelScope.launch {
            _conversation.update { it?.copy(sending = true, error = null, outgoing = text, outgoingFailed = false, outgoingUnconfirmed = false, outgoingImages = prepared.size, stopRequested = false) }
            val operation = java.util.UUID.randomUUID().toString()
            rememberPending(scope, value.session.id, operation)
            try {
                current.sendWithImages(value.session.id, text, prepared, operation)
                forgetPending(scope, value.session.id)
                _pendingImages.value = emptyList()
                _conversation.update { it?.copy(sending = false, draft = "") }
                reloadOpen()
            } catch (error: ProtocolException) {
                if (!unknownOutcome(error)) forgetPending(scope, value.session.id)
                _conversation.update { it?.copy(sending = false, outgoingFailed = !unknownOutcome(error), outgoingUnconfirmed = unknownOutcome(error), error = error.userMessage()) }
            } catch (error: Exception) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = false, outgoingUnconfirmed = true, error = error.userMessage() ?: getApplication<Application>().getString(R.string.chat_image_not_confirmed)) }
            }
        }
    }

    fun draft(text: String) {
        _conversation.update { it?.copy(draft = text) }
    }

    /** The send whose outcome is unknown, kept across restarts so it is inspected, never replayed. */
    private val _pendingOperation = MutableStateFlow<String?>(null)
    val pendingOperation: StateFlow<String?> = _pendingOperation.asStateFlow()

    /** A send belongs to one host and one conversation; a global key mixed them up. */
    private fun pendingKey(scope: String, sessionID: String) = "pendingOperation:$scope:$sessionID"

    private fun rememberPending(scope: String, sessionID: String, operation: String) {
        _pendingOperation.value = operation
        prefs.edit().putString(pendingKey(scope, sessionID), operation).apply()
    }

    private fun forgetPending(scope: String, sessionID: String) {
        _pendingOperation.value = null
        prefs.edit().remove(pendingKey(scope, sessionID)).apply()
    }

    /** Asks the Mac what became of a send whose reply was lost. */
    fun checkPendingSend() {
        val current = repository ?: return
        val value = _conversation.value ?: return
        val id = _pendingOperation.value ?: return
        viewModelScope.launch {
            try {
                val status = current.operation(id)
                val state = status.string("state") ?: "outcome_unknown"
                if (state == "accepted") {
                    forgetPending(storeScope(current.connection), value.session.id)
                    _conversation.update { it?.copy(error = null) }
                    reloadOpen()
                } else {
                    _conversation.update { it?.copy(error = getApplication<Application>().getString(R.string.chat_outcome_unconfirmed_note)) }
                }
            } catch (error: ProtocolException) {
                _conversation.update { it?.copy(error = error.userMessage()) }
            }
        }
    }

    /** Forgets the unknown send after the reader has looked at the Mac. */
    fun acknowledgePendingSend() {
        val current = repository ?: return
        val value = _conversation.value ?: return
        forgetPending(storeScope(current.connection), value.session.id)
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
        // A send whose outcome is unknown must be inspected before another one.
        if (text.isEmpty() || value.sending || _pendingOperation.value != null) return
        val scope = storeScope(current.connection)
        viewModelScope.launch {
            _conversation.update { it?.copy(sending = true, error = null, outgoing = text, outgoingFailed = false, outgoingUnconfirmed = false, outgoingImages = 0, stopRequested = false) }
            val operation = java.util.UUID.randomUUID().toString()
            rememberPending(scope, value.session.id, operation)
            try {
                current.send(value.session.id, text, operation)
                forgetPending(scope, value.session.id)
                _conversation.update { it?.copy(sending = false, draft = "") }
                reloadOpen()
            } catch (error: ProtocolException) {
                if (!unknownOutcome(error)) forgetPending(scope, value.session.id)
                _conversation.update { it?.copy(sending = false, outgoingFailed = !unknownOutcome(error), outgoingUnconfirmed = unknownOutcome(error), error = error.userMessage()) }
            } catch (error: Exception) {
                _conversation.update { it?.copy(sending = false, outgoingFailed = false, outgoingUnconfirmed = true, error = error.userMessage() ?: "The prompt was not confirmed.") }
            }
        }
    }

    /** A lost reply, a dropped link or a timeout leaves the Mac's outcome unknown. */
    private fun unknownOutcome(error: ProtocolException): Boolean =
        error.code in setOf("outcome_unknown", "connection_failed", "link_failed", "timeout")

    fun stop() = interrupt(hard = false)

    /** Hard stop ends the agent's process, not just the current turn; the UI asks first. */
    fun forceStop() = interrupt(hard = true)

    private fun interrupt(hard: Boolean) {
        val current = repository ?: return
        val value = _conversation.value ?: return
        viewModelScope.launch {
            try {
                current.interrupt(value.session.id, hard = hard)
                if (!hard) _conversation.update { it?.copy(stopRequested = true) }
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
            item.pending &&
                (item.sessionID == null || item.sessionID == value.session.id) &&
                item.questions.any { it.prompt == prompt }
        }
        if (match == null) {
            _feedOpen.value = true
            return
        }
        // One request can carry several questions; the card collects one answer
        // per question and submits them together.
        answerQuestion(match.requestID, selections)
    }

    /** The Feed entry for a request, from the list or the open conversation. */
    private fun feedItem(requestID: String): FeedItem? =
        (_shell.value as? ShellState.Connected)?.feed?.firstOrNull { it.requestID == requestID }
            ?: _conversation.value?.feed?.firstOrNull { it.requestID == requestID }

    /** A Feed reply belongs to the Mac that reported the event, not the last opened one. */
    private fun feedHost(item: FeedItem): HostRuntime? =
        hosts.firstOrNull { it.id == item.hostID }
            ?: hosts.firstOrNull { it.repository === repository }

    private fun replyToFeed(requestID: String, send: suspend (BridgeRepository, FeedItem) -> Unit) {
        val item = feedItem(requestID) ?: return
        // A resolved or expired event is a record; it must never be submitted again.
        if (!item.pending || _feedBusy.value) return
        val host = feedHost(item) ?: return
        _feedBusy.value = true
        _feedError.value = null
        viewModelScope.launch {
            try {
                send(host.repository, item)
                if (openHostID == host.id) reloadOpen()
                refresh()
            } catch (error: ProtocolException) {
                _feedError.value = error.userMessage()
                _conversation.update { it?.copy(error = error.userMessage()) }
            } catch (error: Exception) {
                _feedError.value = error.userMessage() ?: error.javaClass.simpleName
            } finally {
                _feedBusy.value = false
            }
        }
    }

    fun answerQuestion(requestID: String, selections: List<String>) = replyToFeed(requestID) { repository, item ->
        repository.answer(requestID, item.kind, selections)
    }

    /** Feed decision that names the event kind and, for a plan, an optional feedback line. */
    fun decideWithKind(requestID: String, kind: String, modeAndFeedback: String) {
        val mode = modeAndFeedback.substringBefore('\u0000')
        val feedback = modeAndFeedback.substringAfter('\u0000', "").ifBlank { null }
        replyToFeed(requestID) { repository, item ->
            repository.reply(requestID, item.kind.ifBlank { kind }, mode, feedback)
        }
    }

    fun decide(requestID: String, mode: String) = replyToFeed(requestID) { repository, item ->
        repository.reply(requestID, item.kind, mode)
    }

    /**
     * Localizes a stable error code. The Bridge's own sentence is English and is
     * only a fallback for codes this build does not know.
     */
    private fun Throwable.userMessage(): String = when (this) {
        is ProtocolException -> {
            val id = when (code) {
                "unauthorized", "forbidden", "scope_denied" -> R.string.error_unauthorized
                "revoked" -> R.string.error_revoked
                "invalid_proof", "replayed_request" -> R.string.error_invalid_proof
                "host_changed", "invalid_identity", "invalid_signature", "invalid_grant" -> R.string.error_identity
                "invalid_certificate" -> R.string.error_invalid_certificate
                "connection_failed", "link_failed", "discovery_failed" -> R.string.error_connection
                "bridge_offline", "bridge_starting", "bridge_replaced" -> R.string.error_bridge_offline
                "relay_unavailable" -> R.string.error_relay_unavailable
                "invalid_endpoint", "relay_configuration" -> R.string.error_invalid_endpoint
                "timeout" -> R.string.error_timeout
                "response_too_large" -> R.string.error_response_too_large
                "operation_not_found" -> R.string.error_operation_not_found
                "outcome_unknown" -> R.string.error_outcome_unknown
                "operation_conflict" -> R.string.error_operation_conflict
                "receipt_capacity", "receipt_storage", "journal_unavailable" -> R.string.error_receipt
                "invalid_enrollment" -> R.string.error_invalid_enrollment
                "enrollment_pending" -> R.string.error_enrollment_pending
                "enrollment_closed" -> R.string.error_enrollment_closed
                "enrollment_expired" -> R.string.error_enrollment_expired
                "request_expired" -> R.string.error_request_expired
                "request_not_found", "request_finished" -> R.string.error_request_missing
                "invalid_pairing" -> R.string.error_invalid_pairing
                "invalid_route", "invalid_response", "invalid_state" -> R.string.error_invalid_response
                "invalid_image" -> R.string.error_invalid_image
                "image_unavailable" -> R.string.error_image_unavailable
                "image_load_failed" -> R.string.error_image_load_failed
                "read_only", "stale_binding", "session_not_found" -> R.string.error_read_only
                "input_busy", "draft_dialog_open" -> R.string.error_input_busy
                "history_unavailable", "history_too_large" -> R.string.error_history
                "file_forbidden", "unsupported_file" -> R.string.error_file
                "invalid_input", "too_large", "prompt_required" -> R.string.error_input_value
                "project_unavailable" -> R.string.error_project
                "task_unavailable" -> R.string.error_task_unavailable
                "launch_unsupported" -> R.string.error_launch_unsupported
                "directory_forbidden", "directory_missing" -> R.string.error_directory
                "invalid_model", "model_unavailable" -> R.string.error_invalid_model
                "model_switch_failed" -> R.string.error_model_switch_failed
                "agent_busy" -> R.string.error_agent_busy
                "speech_permission" -> R.string.error_speech_permission
                "speech_unavailable" -> R.string.error_speech_unavailable
                "speech_too_long" -> R.string.error_speech_too_long
                else -> null
            }
            id?.let { getApplication<Application>().getString(it) } ?: run {
                // Keep an unknown stable code visible and record it, as iOS does.
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Warning,
                    "error",
                    "unhandled error code=$code",
                )
                getApplication<Application>().getString(R.string.error_unknown_code, code)
            }
        }
        else -> message ?: javaClass.simpleName
    }

    override fun onCleared() {
        lives.values.forEach { it.stop() }
        lives.clear()
        networkCallback?.let { callback ->
            runCatching {
                (getApplication<Application>().getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager)
                    .unregisterNetworkCallback(callback)
            }
        }
        discovery.stop()
        backfill?.cancel()
        projectJob?.cancel()
        taskFollow?.cancel()
        super.onCleared()
    }

    private companion object {
        /** iOS fills 64 pages; anything longer is resumed on the next open. */
        const val BACKFILL_PAGES = 64
        const val STORE_COALESCE_MS = 2_000L
        const val OLDER_PAUSE_MS = 800L
        /** Matches the iPhone's approved-Mac limit. */
        const val MAX_HOSTS = 16
        const val MAX_RELAY_ORIGINS = 8
    }

    private suspend fun reloadOpen() {
        // Reads belong to the Mac the conversation was opened on, not whichever
        // Mac happened to be selected last.
        val host = hosts.firstOrNull { it.id == openHostID }
            ?: hosts.firstOrNull { it.repository === repository }
            ?: return
        val current = host.repository
        val value = _conversation.value ?: return
        runCatching {
            val snapshot = current.history(value.session.id)
            val sessions = current.sessions()
            val feed = runCatching { current.feed() }.getOrDefault(emptyList())
                .map { it.copy(hostID = host.id, hostName = host.name) }
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
