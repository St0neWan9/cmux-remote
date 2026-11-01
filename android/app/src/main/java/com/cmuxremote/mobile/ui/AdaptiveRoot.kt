package com.cmuxremote.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.cmuxremote.mobile.ConversationUi
import com.cmuxremote.mobile.CmuxViewModel
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ShellState
import com.cmuxremote.mobile.adaptive.PaneLayout
import com.cmuxremote.mobile.adaptive.PaneLayoutPolicy
import com.cmuxremote.mobile.adaptive.rememberHingeState
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.model.SessionItem
import com.cmuxremote.mobile.model.SessionTrailing
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** The whole app: pairing, then the adaptive browser and conversation shell. */
@Composable
fun CmuxApp(viewModel: CmuxViewModel) {
    val shell by viewModel.shell.collectAsStateWithLifecycle()
    val conversation by viewModel.conversation.collectAsStateWithLifecycle()
    val hinge = rememberHingeState()
    val feedOpen by viewModel.feedOpen.collectAsStateWithLifecycle()
    val project by viewModel.project.collectAsStateWithLifecycle()
    val image by viewModel.image.collectAsStateWithLifecycle()
    val models by viewModel.models.collectAsStateWithLifecycle()
    val modelConfirm by viewModel.modelConfirm.collectAsStateWithLifecycle()
    val selectedKey by viewModel.selectedKey.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    val pendingImages by viewModel.pendingImages.collectAsStateWithLifecycle()
    val taskDetail by viewModel.task.collectAsStateWithLifecycle()
    val toolDetail by viewModel.toolDetail.collectAsStateWithLifecycle()
    val canStart by viewModel.canStart.collectAsStateWithLifecycle()
    val timingOpen by viewModel.timingOpen.collectAsStateWithLifecycle()
    val connectionOpen by viewModel.connectionOpen.collectAsStateWithLifecycle()
    val diagnosticsOpen by viewModel.diagnosticsOpen.collectAsStateWithLifecycle()
    val selectText by viewModel.selectText.collectAsStateWithLifecycle()
    val sidebarOpen by viewModel.sidebarOpen.collectAsStateWithLifecycle()
    val hostFilter by viewModel.hostFilter.collectAsStateWithLifecycle()
    val voiceListening by viewModel.voiceListening.collectAsStateWithLifecycle()
    val voiceError by viewModel.voiceError.collectAsStateWithLifecycle()
    val savedConnection by viewModel.connection.collectAsStateWithLifecycle()
    val pairing by viewModel.pairing.collectAsStateWithLifecycle()
    val addingDevice by viewModel.addingDevice.collectAsStateWithLifecycle()
    val discovered by viewModel.discovered.collectAsStateWithLifecycle()
    val reachable by viewModel.reachable.collectAsStateWithLifecycle()
    val probed by viewModel.probed.collectAsStateWithLifecycle()
    val pendingOperation by viewModel.pendingOperation.collectAsStateWithLifecycle()
    val backgroundSync by viewModel.backgroundSync.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val sortByTime by viewModel.sortByTime.collectAsStateWithLifecycle()
    val workspaceFilter by viewModel.workspaceFilter.collectAsStateWithLifecycle()
    val statusFilter by viewModel.statusFilter.collectAsStateWithLifecycle()
    val collapsed by viewModel.collapsed.collectAsStateWithLifecycle()
    val start by viewModel.start.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    val imageStore = remember { com.cmuxremote.mobile.data.ChatImageStore(context) }
    // Both pickers prepare the chosen bytes the same way: bounded JPEG, no metadata.
    val attachUri: (android.net.Uri) -> Unit = { uri ->
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            runCatching {
                val target = java.io.File(context.cacheDir, "picked-${java.util.UUID.randomUUID()}.img")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                val prepared = imageStore.prepare(target)
                target.delete()
                prepared
            }.onSuccess { prepared -> viewModel.attachImage(prepared.fileName, prepared.base64) }
        }
    }
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia(4),
    ) { uris -> uris.forEach(attachUri) }
    val imageFilePicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocument(),
    ) { uri -> uri?.let(attachUri) }
    // The image is written to a one-off cache file so the chooser can read it; the
    // FileProvider exposes only that directory.
    val shareImage: (ByteArray, String) -> Unit = { bytes, name ->
        runCatching {
            val directory = java.io.File(context.cacheDir, "share").apply { mkdirs() }
            val file = java.io.File(directory, "image-${java.util.UUID.randomUUID()}.jpg")
            file.writeBytes(bytes)
            val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = "image/jpeg"
                putExtra(android.content.Intent.EXTRA_STREAM, uri)
                putExtra(android.content.Intent.EXTRA_TITLE, name)
                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(
                android.content.Intent.createChooser(send, null)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
    val openPicker: () -> Unit = { picker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    val toolRecordTitle = stringResource(R.string.chat_tool_record)
    val selectTextTitle = stringResource(R.string.chat_select_text)
    val connectionUnreachable = stringResource(R.string.connection_unreachable)
    // One scanner serves first-use pairing and adding another Mac.
    var scanning by remember { mutableStateOf(false) }

    LaunchedEffect(conversation?.session?.id) { if (conversation != null) viewModel.loadModels() }

    // Nearby Macs are searched for only while a pairing page is on screen.
    val pairingVisible = shell is ShellState.Pairing || addingDevice
    LaunchedEffect(pairingVisible) {
        if (pairingVisible) viewModel.startDiscovery() else viewModel.stopDiscovery()
    }

    val conversationPane: @Composable (Modifier, (() -> Unit)?) -> Unit = { paneModifier, back ->
        val open = conversation
        if (open != null) {
            ConversationScreen(
                state = open,
                onBack = back,
                onDraft = viewModel::draft,
                onSend = viewModel::send,
                onStop = viewModel::stop,
                modifier = paneModifier,
                models = models,
                onSwitchModel = viewModel::switchModel,
                modelAwaitingConfirmation = modelConfirm,
                onConfirmModelSwitch = viewModel::confirmModelSwitch,
                onCancelModelSwitch = viewModel::cancelModelSwitch,
                offline = probed && !reachable,
                onRetryConnection = viewModel::retryConnection,
                onRename = viewModel::rename,
                onResume = if (canStart) viewModel::resume else null,
                busy = busy,
                onOpenProject = viewModel::openProject,
                onOpenImage = viewModel::openImage,
                onOpenTiming = viewModel::openTiming,
                onOpenTask = viewModel::openTask,
                onAnswerQuestion = viewModel::answerQuestionFromMessage,
                dictating = voiceListening,
                onToggleVoice = viewModel::toggleVoice,
                voiceError = voiceError,
                onOpenDetail = viewModel::openToolDetail,
                onOpenReference = { path -> viewModel.openProjectAt(path) },
                onLoadOlder = viewModel::loadOlder,
                onRefreshConversation = viewModel::refreshOpen,
                onCopyText = { text ->
                    val clipboard = clipboard
                    clipboard?.setText(androidx.compose.ui.text.AnnotatedString(text))
                },
                onShareText = { text ->
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(android.content.Intent.EXTRA_TEXT, text)
                    }
                    context.startActivity(android.content.Intent.createChooser(send, null).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                },
                onQuote = viewModel::appendQuote,
                onSelectText = { text -> viewModel.showText(selectTextTitle, text, false) },
                pendingImages = pendingImages,
                onRemoveImage = viewModel::removeImage,
                onPickImages = if (open.session.writable) openPicker else null,
                onPickImageFile = if (open.session.writable) { { imageFilePicker.launch(arrayOf("image/*")) } } else null,
                onOpenFeed = viewModel::openFeed,
                onForceStop = viewModel::forceStop,
                pendingSend = pendingOperation != null,
                onCheckPending = viewModel::checkPendingSend,
                onAcknowledgePending = viewModel::acknowledgePendingSend,
            )
        } else {
            DetailPane(conversation = null, modifier = paneModifier, viewModel = viewModel)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        val layout = remember(maxWidth, maxHeight, hinge) {
            PaneLayoutPolicy.compute(maxWidth.value, maxHeight.value, hinge)
        }
        val compactDense = maxHeight.value < 560f
        val insets = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)
        val startState = start
        if (startState != null) {
            Box(insets) {
                BackHandler { viewModel.closeStart() }
                StartSessionScreen(
                    workspaces = startState.workspaces,
                    selectedWorkspace = startState.selectedWorkspace,
                    roots = startState.roots,
                    selectedRoot = startState.selectedRoot,
                    agents = startState.agents,
                    selectedAgent = startState.agent,
                    prompt = startState.prompt,
                    busy = startState.busy,
                    error = startState.error,
                    notice = startState.notice,
                    onBack = { viewModel.closeStart() },
                    onPickWorkspace = viewModel::pickStartWorkspace,
                    onPickRoot = viewModel::pickStartRoot,
                    onPickAgent = viewModel::pickStartAgent,
                    onPrompt = viewModel::startPrompt,
                    onStart = viewModel::startSession,
                )
            }
            return@BoxWithConstraints
        }

        when (val state = shell) {
            ShellState.Restoring -> Box(insets, contentAlignment = Alignment.Center) { CircularProgressIndicator() }

            is ShellState.Pairing -> {
                Box(insets) {
                    PairingScreen(
                        state = state,
                        onPair = viewModel::pair,
                        onRetrySaved = viewModel::restore,
                        onScan = { scanning = true },
                        discovered = discovered,
                        approvedHostIDs = viewModel.approvedHostIDs(),
                        onPairDiscovered = viewModel::pairDiscovered,
                    )
                }
            }

            is ShellState.AwaitingOwner -> Box(insets) {
                AwaitingOwnerScreen(
                    hostName = state.hostName,
                    requestID = state.requestID,
                    onCancel = viewModel::cancelPairing,
                )
            }

            is ShellState.Failed -> Box(insets) {
                FailedScreen(code = state.code, message = state.message, onRetry = viewModel::restore)
            }

            is ShellState.Connected -> {
                val listModel = SessionListModel(
                    sessions = state.sessions.map { present(it, context) },
                    hosts = state.hosts.ifEmpty { listOf(state.hostName to state.hostName) },
                    hostFilter = hostFilter,
                    workspaces = state.workspaces,
                    workspaceFilter = workspaceFilter,
                    query = query,
                    sortByTime = sortByTime,
                    statusFilter = statusFilter,
                    collapsed = collapsed,
                    pending = state.pending,
                    pendingCount = state.cachedPending,
                    loading = state.loading,
                    error = state.error,
                    canStart = canStart,
                    selectedID = selectedKey,
                )
                val listActions = SessionListActions(
                    onSelect = { item ->
                        val key = item.hostKey.orEmpty() + ":" + item.id
                        state.sessions.firstOrNull { it.hostID + ":" + it.session.id == key }?.let(viewModel::open)
                    },
                    onOpenFeed = viewModel::openFeed,
                    onStart = viewModel::openStart,
                    onStartInWorkspace = if (canStart) viewModel::startInWorkspace else null,
                    onRefresh = viewModel::refresh,
                    onAddMac = { viewModel.setAddingDevice(true) },
                    onSearch = viewModel::search,
                    onSort = viewModel::setSortByTime,
                    onHost = viewModel::setHostFilter,
                    onWorkspace = viewModel::setWorkspaceFilter,
                    onStatus = viewModel::setStatusFilter,
                    onToggleGroup = viewModel::toggleCollapsed,
                    onConnection = viewModel::openConnection,
                    onOpenSidebar = { viewModel.setSidebar(true) },
                )
                taskDetail?.let { detail ->
                    TaskDetailSheet(
                        task = BackgroundTask(id = detail.task.id, tool = detail.task.tool, status = detail.task.summary, running = detail.task.running),
                        text = detail.text,
                        loading = detail.loading,
                        error = detail.error,
                        onDismiss = viewModel::closeTask,
                        hasMore = detail.nextOffset != null,
                        loadingMore = detail.loadingMore,
                        onLoadMore = viewModel::loadMoreTask,
                    )
                }
                val sessions = state.sessions.map { present(it, context) }
                val selected = conversation?.session
                when (layout) {
                    PaneLayout.Compact -> AppDrawer(
                        open = sidebarOpen,
                        onOpenChange = viewModel::setSidebar,
                        allowsEdgeOpening = conversation == null && project == null && image == null && !feedOpen,
                        drawer = { close ->
                            DrawerContent(
                                hostName = state.hostName,
                                workspaces = state.workspaces.map { (id, title) -> id to title },
                                sessions = listModel.sessions,
                                selectedWorkspace = workspaceFilter,
                                onWorkspace = { id -> viewModel.setWorkspaceFilter(id); close() },
                                onConnection = { close(); viewModel.openConnection() },
                                onAddMac = { close(); viewModel.setAddingDevice(true) },
                                modifier = Modifier.fillMaxSize(),
                            )
                        },
                    ) { Box(insets) {
                        if (project != null) {
                            BackHandler { viewModel.closeProject() }
                            ProjectScreen(
                                title = conversation?.session?.title ?: stringResource(R.string.common_project),
                                changes = project!!.changes,
                                selectedPath = project!!.selectedPath,
                                text = project!!.text,
                                loading = project!!.loading,
                                error = project!!.error,
                                onBack = { viewModel.closeProject() },
                                onSelect = viewModel::selectChange,
                                onOpenPath = viewModel::selectChange,
                                onRefresh = viewModel::openProject,
                            )
                        } else if (image != null) {
                            val shown = image!!
                            BackHandler { viewModel.closeImage() }
                            ImagePreviewScreen(
                                title = shown.reference.name.ifBlank { stringResource(R.string.common_image) },
                                bytes = shown.bytes,
                                loading = shown.loading,
                                error = shown.error,
                                onBack = { viewModel.closeImage() },
                                onShare = shown.bytes?.let { bytes ->
                                    { shareImage(bytes, shown.reference.name) }
                                },
                                onRetry = { viewModel.openImage(shown.reference) },
                            )
                        } else if (feedOpen) {
                            BackHandler { viewModel.closeFeed() }
                            FeedScreen(
                                items = (shell as? ShellState.Connected)?.feed ?: emptyList(),
                                onBack = { viewModel.closeFeed() },
                                onAnswer = viewModel::answerQuestion,
                                onDecide = viewModel::decideWithKind,
                            )
                        } else if (conversation != null) {
                            BackHandler { viewModel.close() }
                            conversationPane(Modifier.fillMaxSize(), { viewModel.close() })
                        } else {
                            SessionListScreen(
                                model = listModel,
                                actions = listActions,
                                dense = compactDense,
                            )
                        }
                    } }

                    is PaneLayout.TwoPane -> Row(insets) {
                        SessionBrowserPane(model = listModel, actions = listActions, modifier = Modifier.width(layout.browserWidthDp.dp))
                        VerticalLine()
                        if (project != null) {
                            ProjectScreen(
                                title = conversation?.session?.title ?: stringResource(R.string.common_project),
                                changes = project!!.changes,
                                selectedPath = project!!.selectedPath,
                                text = project!!.text,
                                loading = project!!.loading,
                                error = project!!.error,
                                onBack = { viewModel.closeProject() },
                                onSelect = viewModel::selectChange,
                                onOpenPath = viewModel::selectChange,
                                onRefresh = viewModel::openProject,
                                modifier = Modifier.weight(1f),
                            )
                        } else if (image != null) {
                            val shown = image!!
                            ImagePreviewScreen(
                                title = shown.reference.name.ifBlank { stringResource(R.string.common_image) },
                                bytes = shown.bytes,
                                loading = shown.loading,
                                error = shown.error,
                                onBack = { viewModel.closeImage() },
                                modifier = Modifier.weight(1f),
                                onShare = shown.bytes?.let { bytes ->
                                    { shareImage(bytes, shown.reference.name) }
                                },
                                onRetry = { viewModel.openImage(shown.reference) },
                            )
                        } else if (feedOpen) {
                            FeedScreen(
                                items = state.feed,
                                onBack = viewModel::closeFeed,
                                onAnswer = viewModel::answerQuestion,
                                onDecide = viewModel::decideWithKind,
                                modifier = Modifier.weight(1f),
                            )
                        } else {
                            conversationPane(Modifier.weight(1f), null)
                        }
                    }

                    is PaneLayout.ThreePane -> Row(insets) {
                        SessionBrowserPane(model = listModel, actions = listActions, modifier = Modifier.width(layout.browserWidthDp.dp))
                        VerticalLine()
                        conversationPane(Modifier.weight(1f), null)
                        VerticalLine()
                        SupportingPane(
                            messages = conversation?.messages ?: emptyList(),
                            modifier = Modifier.width(layout.supportingWidthDp.dp),
                        )
                    }

                    is PaneLayout.Tabletop -> Box(insets) {
                        val open = conversation
                        if (open == null) {
                            SessionListScreen(
                                model = if (compactDense) listModel.copy(sessions = listModel.sessions) else listModel,
                                actions = listActions,
                                dense = compactDense,
                            )
                        } else {
                            TabletopScreen(
                                state = open,
                                layout = layout,
                                onDraft = viewModel::draft,
                                onSend = viewModel::send,
                                onStop = viewModel::stop,
                                onAnswer = viewModel::answerQuestion,
                                onDecide = viewModel::decide,
                            )
                        }
                    }
                }
            }
        }

        // Pages that open over whichever shell is behind them. They are composed
        // last, so their back handlers win over the shell's.
        if (connectionOpen) {
            BackHandler { viewModel.closeConnection() }
            savedConnection?.let { saved ->
                ConnectionDetailScreen(
                    info = ConnectionInfo(
                        hostID = saved.host.id,
                        name = saved.host.name,
                        endpoint = "${saved.endpoint.host}:${saved.endpoint.port}",
                        identity = saved.host.id,
                        certificate = saved.host.certificateSHA256,
                        protocolName = "v2 HTTPS · link v3",
                        reachable = reachable,
                        capabilities = saved.scope.capabilities.map { it.raw },
                        overRelay = viewModel.overRelay,
                        keystoreBacking = viewModel.keyBacking,
                        error = if (probed && !reachable) connectionUnreachable else null,
                    ),
                    loading = !probed,
                    backgroundSync = backgroundSync,
                    onBackgroundSync = viewModel::setBackgroundSync,
                    onRefresh = viewModel::refreshConnection,
                    onRemove = {
                        viewModel.removeMac(saved.host.id)
                        viewModel.closeConnection()
                    },
                    onDiagnostics = viewModel::openDiagnostics,
                    onBack = viewModel::closeConnection,
                )
            }
            LaunchedEffect(Unit) { viewModel.refreshConnection() }
        }

        if (diagnosticsOpen) {
            BackHandler { viewModel.closeDiagnostics() }
            DiagnosticLogScreen(onBack = viewModel::closeDiagnostics)
        }

        toolDetail?.let { detail ->
            BackHandler { viewModel.closeToolDetail() }
            val fields = if (detail.field == "diff") listOf("diff") else listOf("input", "output")
            val message = conversation?.messages?.firstOrNull { it.id == detail.messageID }
            ToolDetailScreen(
                title = message?.filePath ?: message?.toolName ?: toolRecordTitle,
                fields = fields,
                selectedField = fields.indexOf(detail.field).coerceAtLeast(0),
                text = detail.text,
                hasMore = detail.hasMore,
                hasPrevious = detail.hasPrevious,
                loading = detail.loading,
                error = detail.error,
                onSelectField = { index -> viewModel.openToolDetail(detail.messageID, fields[index]) },
                onOlder = viewModel::loadMoreToolDetail,
                onNewer = viewModel::previousToolDetailPage,
                onRefresh = { viewModel.openToolDetail(detail.messageID, detail.field) },
                onBack = viewModel::closeToolDetail,
                modifier = Modifier.windowInsetsPadding(WindowInsets.safeDrawing),
            )
        }

        if (timingOpen) {
            BackHandler { viewModel.closeTiming() }
            TimingScreen(
                recordedSeconds = conversation?.recordedRunSeconds,
                turns = conversation?.recordedTurnCount ?: 0,
                onBack = viewModel::closeTiming,
            )
        }

        selectText?.let { request ->
            BackHandler { viewModel.closeText() }
            SelectTextScreen(
                title = request.title,
                text = request.text,
                monospaced = request.monospaced,
                onBack = viewModel::closeText,
            )
        }

        if (addingDevice) {
            BackHandler { viewModel.setAddingDevice(false) }
            when (val state = pairing) {
                is ShellState.AwaitingOwner -> AwaitingOwnerScreen(
                    hostName = state.hostName,
                    requestID = state.requestID,
                    onCancel = viewModel::cancelPairing,
                )
                is ShellState.Failed -> FailedScreen(
                    code = state.code,
                    message = state.message,
                    onRetry = { viewModel.setAddingDevice(false); viewModel.restore() },
                )
                else -> PairingScreen(
                    state = state as? ShellState.Pairing ?: ShellState.Pairing(),
                    onPair = viewModel::pair,
                    onRetrySaved = { viewModel.setAddingDevice(false); viewModel.restore() },
                    onScan = { scanning = true },
                    discovered = discovered,
                    approvedHostIDs = viewModel.approvedHostIDs(),
                    onPairDiscovered = viewModel::pairDiscovered,
                    onBack = { viewModel.setAddingDevice(false) },
                )
            }
        }

        if (scanning) {
            QrScannerScreen(
                onScanned = { code ->
                    scanning = false
                    viewModel.pair(code)
                },
                onCancel = { scanning = false },
            )
        }
    }
}

@Composable
private fun DetailPane(
    conversation: ConversationUi?,
    modifier: Modifier,
    viewModel: CmuxViewModel,
) {
    Box(modifier.fillMaxHeight()) {
        if (conversation == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                androidx.compose.material3.Text(
                    stringResource(R.string.common_select_conversation),
                    color = MobileDesign.Muted,
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            ConversationScreen(
                state = conversation,
                onBack = null,
                onDraft = viewModel::draft,
                onSend = viewModel::send,
                onStop = viewModel::stop,
            )
        }
    }
}

@Composable
private fun VerticalLine() {
    Box(Modifier.width(1.dp).fillMaxHeight().background(MobileDesign.Line))
}

/** Maps a Bridge descriptor to the row model the list renders. */
private fun present(hosted: com.cmuxremote.mobile.HostedSession, context: android.content.Context): SessionItem {
    val session = hosted.session
    return SessionItem(
        id = session.id,
        title = session.title,
        agent = session.agent.replaceFirstChar { it.uppercase() },
        age = relativeAge(session.updatedAt, context),
        workspaceKey = session.workspaceID ?: "",
        hostKey = hosted.hostID,
        updatedAt = runCatching { java.time.Instant.parse(session.updatedAt) }.getOrNull(),
        trailing = when {
            session.working -> SessionTrailing.Working
            session.resumable -> SessionTrailing.Resumable
            !session.writable -> SessionTrailing.Locked
            else -> SessionTrailing.None
        },
    )
}

private fun presentLegacy(session: SessionDescriptor, context: android.content.Context): SessionItem = SessionItem(
    id = session.id,
    title = session.title,
    agent = session.agent.replaceFirstChar { it.uppercase() },
    age = relativeAge(session.updatedAt, context),
    workspaceKey = session.workspaceID ?: "",
    trailing = when {
        session.working -> SessionTrailing.Working
        session.resumable -> SessionTrailing.Resumable
        !session.writable -> SessionTrailing.Locked
        else -> SessionTrailing.None
    },
)

/** A short relative age from the Bridge's ISO-8601 timestamp. */
private fun relativeAge(timestamp: String?, context: android.content.Context): String {
    if (timestamp == null) return ""
    val instant = runCatching { java.time.Instant.parse(timestamp) }.getOrNull() ?: return ""
    val minutes = java.time.Duration.between(instant, java.time.Instant.now()).toMinutes()
    return when {
        minutes < 1 -> context.getString(R.string.common_just_now)
        minutes < 60 -> context.getString(R.string.common_minutes_ago, minutes.toInt())
        minutes < 24 * 60 -> context.getString(R.string.common_hours_ago, (minutes / 60).toInt())
        else -> context.getString(R.string.common_days_ago, (minutes / (24 * 60)).toInt())
    }
}
