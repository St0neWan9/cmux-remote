package com.cmuxremote.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import com.cmuxremote.mobile.GroupUi
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
    val imagePreparing by viewModel.imagePreparing.collectAsStateWithLifecycle()
    val imageError by viewModel.imageError.collectAsStateWithLifecycle()
    val taskDetail by viewModel.task.collectAsStateWithLifecycle()
    val toolDetail by viewModel.toolDetail.collectAsStateWithLifecycle()
    val groupPage by viewModel.group.collectAsStateWithLifecycle()
    val canStart by viewModel.canStart.collectAsStateWithLifecycle()
    val timingOpen by viewModel.timingOpen.collectAsStateWithLifecycle()
    val connectionOpen by viewModel.connectionOpen.collectAsStateWithLifecycle()
    val diagnosticsOpen by viewModel.diagnosticsOpen.collectAsStateWithLifecycle()
    val selectText by viewModel.selectText.collectAsStateWithLifecycle()
    val sidebarOpen by viewModel.sidebarOpen.collectAsStateWithLifecycle()
    val hostFilter by viewModel.hostFilter.collectAsStateWithLifecycle()
    val voiceListening by viewModel.voiceListening.collectAsStateWithLifecycle()
    val voiceError by viewModel.voiceError.collectAsStateWithLifecycle()
    val speechDraft by viewModel.speechDraft.collectAsStateWithLifecycle()
    val speechState by viewModel.speechState.collectAsStateWithLifecycle()
    val savedConnection by viewModel.connection.collectAsStateWithLifecycle()
    val pairing by viewModel.pairing.collectAsStateWithLifecycle()
    val addingDevice by viewModel.addingDevice.collectAsStateWithLifecycle()
    val discovered by viewModel.discovered.collectAsStateWithLifecycle()
    val relayOrigins by viewModel.relayOrigins.collectAsStateWithLifecycle()
    val relayHosts by viewModel.relayHosts.collectAsStateWithLifecycle()
    val relayLoading by viewModel.relayLoading.collectAsStateWithLifecycle()
    val relayError by viewModel.relayError.collectAsStateWithLifecycle()
    val reachable by viewModel.reachable.collectAsStateWithLifecycle()
    val probed by viewModel.probed.collectAsStateWithLifecycle()
    val connecting by viewModel.connecting.collectAsStateWithLifecycle()
    val hostReachable by viewModel.hostReachable.collectAsStateWithLifecycle()
    val pendingOperation by viewModel.pendingOperation.collectAsStateWithLifecycle()
    val feedBusy by viewModel.feedBusy.collectAsStateWithLifecycle()
    val feedError by viewModel.feedError.collectAsStateWithLifecycle()
    val feedHost by viewModel.feedHost.collectAsStateWithLifecycle()
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
        viewModel.beginImagePreparation()
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                val target = java.io.File(context.cacheDir, "picked-${java.util.UUID.randomUUID()}.img")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                val prepared = imageStore.prepare(target)
                target.delete()
                viewModel.attachImage(prepared.fileName, prepared.base64)
            } catch (_: Exception) {
                viewModel.endImagePreparation(context.getString(R.string.chat_image_prepare_failed))
            } finally {
                viewModel.endImagePreparation()
            }
        }
    }
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia(4),
    ) { uris -> uris.forEach(attachUri) }
    val imageFilePicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris -> uris.forEach(attachUri) }
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

    // Pairing needs nearby Macs; a paired Mac also needs discovery so a moved
    // endpoint can be found again without pairing from scratch.
    val pairingVisible = shell is ShellState.Pairing || addingDevice
    val discover = pairingVisible || shell is ShellState.Connected
    LaunchedEffect(discover) {
        if (discover) {
            viewModel.startDiscovery()
        } else {
            viewModel.stopDiscovery()
        }
    }
    LaunchedEffect(pairingVisible) {
        if (pairingVisible) viewModel.refreshRelayDirectory()
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
                connecting = connecting,
                onRetryConnection = viewModel::retryConnection,
                onRename = viewModel::rename,
                onResume = if (canStart) viewModel::resume else null,
                busy = busy,
                feedBusy = feedBusy,
                canControl = viewModel.allows(com.cmuxremote.mobile.protocol.ClientCapability.ConversationControl),
                hostName = viewModel.openHostName(),
                // Each entry is shown only when this conversation's Mac granted it.
                onOpenProject = if (viewModel.allows(com.cmuxremote.mobile.protocol.ClientCapability.ProjectRead)) {
                    viewModel::openProject
                } else {
                    null
                },
                onOpenImage = viewModel::openImage,
                onOpenTiming = viewModel::openTiming,
                onOpenTask = viewModel::openTask,
                onAnswerQuestion = if (viewModel.allows(com.cmuxremote.mobile.protocol.ClientCapability.FeedReply)) {
                    viewModel::answerQuestionFromMessage
                } else {
                    null
                },
                dictating = voiceListening,
                onToggleVoice = if (open.session.writable && !open.session.working && !busy) viewModel::toggleVoice else null,
                voiceError = voiceError,
                speechDraft = speechDraft,
                speechListening = speechState == com.cmuxremote.mobile.SpeechState.Listening,
                onFinishVoice = viewModel::finishVoice,
                onUseSpeech = viewModel::useSpeechDraft,
                onCancelSpeech = viewModel::cancelSpeechDraft,
                onOpenDetail = viewModel::openToolDetail,
                onOpenReference = { path -> viewModel.openProjectAt(path) },
                onOpenGroup = viewModel::openGroup,
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
                imagePreparing = imagePreparing,
                imageError = imageError,
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
                    path = startState.path,
                    folders = startState.folders,
                    foldersTruncated = startState.foldersTruncated,
                    foldersLoading = startState.foldersLoading,
                    foldersError = startState.foldersError,
                    agents = startState.agents,
                    selectedAgent = startState.agent,
                    prompt = startState.prompt,
                    busy = startState.busy,
                    uncertain = startState.uncertain,
                    error = startState.error,
                    notice = startState.notice,
                    onBack = { viewModel.closeStart() },
                    onPickWorkspace = viewModel::pickStartWorkspace,
                    onPickRoot = viewModel::pickStartRoot,
                    onRefreshRoots = viewModel::refreshStartRoots,
                    onOpenFolder = viewModel::openStartFolder,
                    onUpFolder = viewModel::upStartFolder,
                    onPickAgent = viewModel::pickStartAgent,
                    onPrompt = viewModel::startPrompt,
                    onStart = viewModel::startSession,
                    onStartFresh = viewModel::startSessionFresh,
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
                        relayOrigins = relayOrigins,
                        relayHosts = relayHosts,
                        relayLoading = relayLoading,
                        relayError = relayError,
                        onAddRelay = viewModel::addRelayOrigin,
                        onRemoveRelay = viewModel::removeRelayOrigin,
                        onRefreshRelay = viewModel::refreshRelayDirectory,
                        onPairListed = viewModel::pairListed,
                        onResetIdentity = viewModel::resetIdentity,
                        onPairLegacy = viewModel::pairLegacy,
                    )
                }
            }

            is ShellState.AwaitingOwner -> Box(insets) {
                AwaitingOwnerScreen(
                    hostName = state.hostName,
                    requestID = state.requestID,
                    clientID = state.clientID,
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
                    hostReachable = hostReachable,
                    canReadConversations = viewModel.canReadConversations(),
                )
                val listActions = SessionListActions(
                    onSelect = { item ->
                        val key = item.hostKey.orEmpty() + ":" + item.id
                        state.sessions.firstOrNull { it.hostID + ":" + it.session.id == key }?.let(viewModel::open)
                    },
                    onOpenFeed = viewModel::openFeed,
                    onOpenFeedHost = { id -> viewModel.openFeed(id) },
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
                        messages = detail.messages,
                        command = detail.command,
                        totalBytes = detail.totalBytes,
                        running = detail.running,
                    )
                }
                val sessions = state.sessions.map { present(it, context) }
                val selected = conversation?.session
                when (layout) {
                    PaneLayout.Compact -> AppDrawer(
                        open = sidebarOpen,
                        onOpenChange = viewModel::setSidebar,
                        allowsEdgeOpening = conversation == null && project == null && image == null &&
                            !feedOpen && !addingDevice && !connectionOpen && !diagnosticsOpen,
                        drawer = { close ->
                            DrawerContent(
                                model = listModel,
                                actions = listActions,
                                onSelectSession = { session ->
                                    close()
                                    listActions.onSelect(session)
                                },
                                onHostConnection = { id ->
                                    close()
                                    viewModel.openConnection(id)
                                },
                                closed = close,
                                modifier = Modifier.fillMaxSize(),
                            )
                        },
                    ) { Box(insets) {
                        if (project != null) {
                            BackHandler { viewModel.closeProject() }
                            PushIn {
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
                                mode = project!!.mode,
                                inputPath = project!!.inputPath,
                                onPathChange = viewModel::setProjectPath,
                                onOpenPathInput = viewModel::openProjectPathInput,
                                onShowChanges = viewModel::showProjectChanges,
                                onShowDiff = viewModel::showProjectDiff,
                                onRefresh = viewModel::refreshProject,
                            )
                            }
                        } else if (image != null) {
                            val shown = image!!
                            BackHandler { viewModel.closeImage() }
                            PushIn {
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
                            }
                        } else if (feedOpen) {
                            BackHandler { viewModel.closeFeed() }
                            PushIn {
                            FeedScreen(
                                items = ((shell as? ShellState.Connected)?.feed ?: emptyList()).filter { feedHost == null || it.hostID == feedHost },
                                onBack = { viewModel.closeFeed() },
                                onAnswer = viewModel::answerQuestion,
                                onDecide = viewModel::decideWithKind,
                                busy = feedBusy,
                                loading = (shell as? ShellState.Connected)?.loading == true,
                                error = feedError ?: (shell as? ShellState.Connected)?.error,
                            )
                            }
                        } else if (conversation != null) {
                            BackHandler { viewModel.close() }
                            PushIn { conversationPane(Modifier.fillMaxSize(), { viewModel.close() }) }
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
                                mode = project!!.mode,
                                inputPath = project!!.inputPath,
                                onPathChange = viewModel::setProjectPath,
                                onOpenPathInput = viewModel::openProjectPathInput,
                                onShowChanges = viewModel::showProjectChanges,
                                onShowDiff = viewModel::showProjectDiff,
                                onRefresh = viewModel::refreshProject,
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
                                items = state.feed.filter { feedHost == null || it.hostID == feedHost },
                                onBack = viewModel::closeFeed,
                                onAnswer = viewModel::answerQuestion,
                                onDecide = viewModel::decideWithKind,
                                modifier = Modifier.weight(1f),
                                busy = feedBusy,
                                loading = state.loading,
                                error = feedError ?: state.error,
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
                        reachable = hostReachable[saved.host.id] ?: reachable,
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

        groupPage?.let { page ->
            BackHandler { viewModel.closeGroup() }
            val rows = toolRowModels(page.messages)
            Column(
                Modifier
                    .fillMaxSize()
                    .background(MobileDesign.Canvas)
                    .windowInsetsPadding(WindowInsets.safeDrawing),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    androidx.compose.material3.Icon(
                        androidx.compose.material.icons.Icons.Rounded.ChevronLeft,
                        contentDescription = stringResource(R.string.common_back),
                        tint = MobileDesign.Ink,
                        modifier = Modifier.size(36.dp).clickable { viewModel.closeGroup() }.padding(6.dp),
                    )
                    Text(
                        text = stringResource(R.string.chat_operation_count_plural, rows.size),
                        color = MobileDesign.Ink,
                        style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                    )
                }
                ActivityGroupPage(
                    rows = rows,
                    onOpenDetail = { row ->
                        viewModel.openToolDetail(row.id, if (row.kind == "file_edit") "diff" else "output")
                    },
                    onOpenReference = { path -> viewModel.openProjectAt(path) },
                )
            }
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
                    clientID = state.clientID,
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
                    relayOrigins = relayOrigins,
                    relayHosts = relayHosts,
                    relayLoading = relayLoading,
                    relayError = relayError,
                    onAddRelay = viewModel::addRelayOrigin,
                    onRemoveRelay = viewModel::removeRelayOrigin,
                    onRefreshRelay = viewModel::refreshRelayDirectory,
                    onPairListed = viewModel::pairListed,
                    onResetIdentity = viewModel::resetIdentity,
                        onPairLegacy = viewModel::pairLegacy,
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
        hostName = hosted.hostName,
        updatedAt = runCatching { java.time.Instant.parse(session.updatedAt) }.getOrNull(),
        cwd = session.cwd,
        writable = session.writable,
        working = session.working,
        resumable = session.resumable,
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
    updatedAt = runCatching { java.time.Instant.parse(session.updatedAt) }.getOrNull(),
    cwd = session.cwd,
    writable = session.writable,
    working = session.working,
    resumable = session.resumable,
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


/** A detail page enters from the trailing edge, like a pushed page. */
@androidx.compose.runtime.Composable
private fun PushIn(content: @androidx.compose.runtime.Composable () -> Unit) {
    AnimatedVisibility(
        visible = true,
        enter = slideInHorizontally(initialOffsetX = { it / 3 }) + fadeIn(),
    ) { content() }
}
