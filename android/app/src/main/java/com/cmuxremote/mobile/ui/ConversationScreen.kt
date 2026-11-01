package com.cmuxremote.mobile.ui

import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.FloatingActionButton
import androidx.compose.foundation.layout.Arrangement as LayoutArrangement
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.ConversationUi
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.data.ChatMessage
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.markdown.MarkdownText
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** One conversation: header, transcript, preview, draft and the send/stop control. */
@Composable
fun ConversationScreen(
    state: ConversationUi,
    onBack: (() -> Unit)? = null,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
    models: List<ModelOption> = emptyList(),
    onSwitchModel: (ModelOption) -> Unit = {},
    modelAwaitingConfirmation: ModelOption? = null,
    onConfirmModelSwitch: (() -> Unit)? = null,
    onCancelModelSwitch: (() -> Unit)? = null,
    onRename: (String) -> Unit = {},
    onResume: (() -> Unit)? = null,
    onCopyText: ((String) -> Unit)? = null,
    onShareText: ((String) -> Unit)? = null,
    onQuote: ((String) -> Unit)? = null,
    onSelectText: ((String) -> Unit)? = null,
    busy: Boolean = false,
    feedBusy: Boolean = false,
    /** The Mac granted conversationControl; writing is refused without it. */
    canControl: Boolean = true,
    /** The Mac this conversation lives on, shown in the subtitle. */
    hostName: String? = null,
    onOpenProject: (() -> Unit)? = null,
    onOpenTiming: (() -> Unit)? = null,
    onOpenImage: ((com.cmuxremote.mobile.data.ImageReference) -> Unit)? = null,
    onAnswerQuestion: ((String, List<String>) -> Unit)? = null,
    onOpenDetail: ((String, String) -> Unit)? = null,
    onOpenReference: ((String) -> Unit)? = null,
    /** Opens the whole group, not just its newest slice. */
    onOpenGroup: ((List<ChatMessage>) -> Unit)? = null,
    onOpenTask: ((com.cmuxremote.mobile.data.BackgroundTaskInfo) -> Unit)? = null,
    onLoadOlder: ((Boolean) -> Unit)? = null,
    onRefreshConversation: (() -> Unit)? = null,
    pendingImages: List<Pair<String, String>> = emptyList(),
    /** Images still being compressed. */
    imagePreparing: Int = 0,
    imageError: String? = null,
    onRemoveImage: (Int) -> Unit = {},
    onPickImages: (() -> Unit)? = null,
    dictating: Boolean = false,
    onToggleVoice: (() -> Unit)? = null,
    voiceError: String? = null,
    /** The dictation's own draft and controls. */
    speechDraft: String? = null,
    speechListening: Boolean = false,
    onFinishVoice: (() -> Unit)? = null,
    onUseSpeech: (() -> Unit)? = null,
    onCancelSpeech: (() -> Unit)? = null,
    onForceStop: (() -> Unit)? = null,
    pendingSend: Boolean = false,
    onCheckPending: (() -> Unit)? = null,
    onAcknowledgePending: (() -> Unit)? = null,
    offline: Boolean = false,
    /** A redial is in flight, as opposed to a proven failure. */
    connecting: Boolean = false,
    onRetryConnection: (() -> Unit)? = null,
    onPickImageFile: (() -> Unit)? = null,
    onOpenFeed: (() -> Unit)? = null,
) {
    var renaming by remember { mutableStateOf(false) }
    var previewImage by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        ConversationHeader(
            title = state.session.title,
            subtitle = subtitle(state.session, state.agentModel, hostName, LocalContext.current),
            onBack = onBack,
            models = models,
            currentModel = state.agentModel,
            canSwitchModel = canControl && state.session.writable && !state.session.working,
            onSwitchModel = onSwitchModel,
            onRename = if (canControl && state.session.writable) {
                { renaming = true }
            } else {
                null
            },
            onOpenProject = onOpenProject,
            onOpenFeed = onOpenFeed,
            onOpenTiming = onOpenTiming,
            onRefresh = onRefreshConversation,
            onForceStop = onForceStop?.takeIf { state.session.working && canControl },
            onSoftStop = if (state.session.working) onStop else null,
        )
        // A white capsule floats over the page, as on the iPhone; the failed state
        // keeps a retry, the connecting state explains the wait.
        if (connecting || offline) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
                Row(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .clip(RoundedCornerShape(50))
                        .background(MobileDesign.Canvas)
                        .border(androidx.compose.foundation.BorderStroke(0.5.dp, MobileDesign.Line), RoundedCornerShape(50))
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (connecting) {
                        WorkingIndicator(size = 14.dp)
                        Text(stringResource(R.string.chat_reconnecting), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    } else {
                        Icon(Icons.Rounded.WifiOff, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(15.dp))
                        Text(stringResource(R.string.chat_connection_lost), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                        if (onRetryConnection != null) {
                            Text(
                                text = stringResource(R.string.common_retry),
                                color = MobileDesign.Accent,
                                style = MaterialTheme.typography.labelMedium,
                                modifier = Modifier.clickable(onClick = onRetryConnection).padding(vertical = 2.dp),
                            )
                        }
                    }
                }
            }
        }
        ConversationTimeline(
            state = state,
            offline = offline,
            modifier = Modifier.weight(1f),
            onOpenImage = onOpenImage,
            onAnswerQuestion = onAnswerQuestion,
            onOpenDetail = onOpenDetail,
            onOpenReference = onOpenReference,
            onOpenGroup = onOpenGroup,
            onLoadOlder = onLoadOlder,
            onRefreshConversation = onRefreshConversation,
            onCopyText = onCopyText,
            onShareText = onShareText,
            onQuote = onQuote,
            onSelectText = onSelectText,
            feedBusy = feedBusy,
        )
        if (state.backgroundTasks.isNotEmpty() && onOpenTask != null) {
            BackgroundTasksRow(
                tasks = state.backgroundTasks.map {
                    BackgroundTask(id = it.id, tool = it.tool, status = it.summary, running = it.running)
                },
                onOpen = { chip ->
                    state.backgroundTasks.firstOrNull { it.id == chip.id }?.let(onOpenTask)
                },
                modifier = Modifier.padding(horizontal = 14.dp),
            )
        }
        if (state.session.resumable && !state.session.writable && onResume != null) {
            ResumeBanner(onResume = onResume, busy = busy)
        }
        if (imagePreparing > 0) {
            Text(
                stringResource(R.string.chat_preparing_image),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 14.dp),
            )
        }
        if (imageError != null) {
            Text(
                imageError,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 14.dp),
            )
        }
        if (pendingImages.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                pendingImages.forEachIndexed { index, (name, base64) ->
                    val bitmap = remember(base64) {
                        runCatching {
                            val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
                            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        }.getOrNull()
                    }
                    Box(
                        modifier = Modifier
                            .size(76.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(MobileDesign.Soft)
                            .then(
                                if (bitmap != null) Modifier.clickable { previewImage = bitmap } else Modifier,
                            ),
                    ) {
                        if (bitmap != null) {
                            androidx.compose.foundation.Image(
                                bitmap = bitmap.asImageBitmap(),
                                contentDescription = name,
                                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                        } else {
                            Text(
                                text = name,
                                color = MobileDesign.Muted,
                                style = MaterialTheme.typography.labelMedium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(6.dp),
                            )
                        }
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .size(18.dp)
                                .background(MobileDesign.Ink, CircleShape)
                                .clickable { onRemoveImage(index) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("✕", color = MobileDesign.Canvas, fontSize = 10.sp)
                        }
                    }
                }
            }
        }
        if (pendingSend) {
            PendingSendBanner(
                onCheck = onCheckPending,
                onAcknowledge = onAcknowledgePending,
                modifier = Modifier.padding(horizontal = 14.dp),
            )
        }
        if (speechDraft != null || speechListening) {
            SpeechDraftStrip(
                text = speechDraft.orEmpty(),
                listening = speechListening,
                onFinish = onFinishVoice,
                onUse = onUseSpeech,
                onCancel = onCancelSpeech,
            )
        }
        ComposerArea(
            draft = state.draft,
            onDraftChange = onDraft,
            onSend = onSend,
            onStop = onStop,
            working = state.session.working,
            canSend = canControl && state.session.writable,
            sending = state.sending,
            hasBackgroundTasks = state.backgroundTasks.any { it.running },
            // The timeline carries the error row; a second copy under the composer
            // made every failure appear twice.
            error = null,
            hasImages = pendingImages.isNotEmpty(),
            onPickImages = onPickImages,
            onPickImageFile = onPickImageFile,
            onOpenProject = onOpenProject,
            onOpenFeed = onOpenFeed,
            dictating = dictating,
            onToggleVoice = onToggleVoice,
            voiceError = voiceError,
        )
    }
    // A prepared image can be inspected before it is sent.
    previewImage?.let { bitmap ->
        androidx.compose.ui.window.Dialog(onDismissRequest = { previewImage = null }) {
            Box(
                modifier = Modifier.fillMaxSize().clickable { previewImage = null },
                contentAlignment = Alignment.Center,
            ) {
                androidx.compose.foundation.Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
    if (renaming) {
        RenameDialog(
            initial = state.session.title,
            onDismiss = { renaming = false },
            onConfirm = { title -> renaming = false; onRename(title) },
        )
    }
    if (modelAwaitingConfirmation != null && onConfirmModelSwitch != null) {
        AlertDialog(
            onDismissRequest = { onCancelModelSwitch?.invoke() },
            title = { Text(stringResource(R.string.model_confirm_title), color = MobileDesign.Ink) },
            text = {
                Text(
                    stringResource(R.string.model_confirm_note, modelAwaitingConfirmation.label),
                    color = MobileDesign.Muted,
                )
            },
            confirmButton = {
                TextButton(onClick = onConfirmModelSwitch) {
                    Text(stringResource(R.string.common_switch))
                }
            },
            dismissButton = {
                TextButton(onClick = { onCancelModelSwitch?.invoke() }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

private fun subtitle(session: SessionDescriptor, agentModel: String?, hostName: String?, context: Context): String =
    listOf(
        session.agent.replaceFirstChar { it.uppercase() },
        agentModel ?: "",
        // The iPhone names the Mac, not an opaque workspace id.
        hostName ?: "",
        stateLabel(session, context),
    )
        .filter { it.isNotEmpty() }
        .joinToString(" · ")

private fun stateLabel(session: SessionDescriptor, context: Context): String = when {
    session.working -> context.getString(R.string.common_working)
    session.resumable -> context.getString(R.string.common_resumable)
    !session.writable -> context.getString(R.string.common_read_only)
    else -> ""
}

@Composable
fun ConversationHeader(
    title: String,
    subtitle: String,
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    models: List<ModelOption> = emptyList(),
    currentModel: String? = null,
    canSwitchModel: Boolean = false,
    onSwitchModel: (ModelOption) -> Unit = {},
    onRename: (() -> Unit)? = null,
    onOpenProject: (() -> Unit)? = null,
    onOpenFeed: (() -> Unit)? = null,
    onOpenTiming: (() -> Unit)? = null,
    onRefresh: (() -> Unit)? = null,
    onForceStop: (() -> Unit)? = null,
    onSoftStop: (() -> Unit)? = null,
) {
    var confirmForceStop by remember { mutableStateOf(false) }
    Row(
        modifier = modifier
            .fillMaxWidth()
            // A frosted approximation: a near-white gradient with the page showing
            // through, since Compose has no system glass material.
            .background(
                Brush.verticalGradient(
                    listOf(MobileDesign.Canvas.copy(alpha = 0.98f), MobileDesign.Canvas.copy(alpha = 0.88f)),
                ),
            )
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (onBack != null) {
            Box(
                modifier = Modifier.size(44.dp).shadow(3.dp, CircleShape).background(MobileDesign.Canvas, CircleShape).border(0.5.dp, MobileDesign.Line, CircleShape).clip(CircleShape).clickable(onClick = onBack).testTag("chat.back"),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.ChevronLeft, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink, modifier = Modifier.size(22.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (models.isNotEmpty()) {
            ModelMenu(current = currentModel, options = models, enabled = canSwitchModel, onPick = onSwitchModel)
        }
        Box {
            var open by remember { mutableStateOf(false) }
            Icon(
                Icons.Rounded.MoreVert,
                contentDescription = stringResource(R.string.common_more),
                tint = MobileDesign.Muted,
                modifier = Modifier
                    .size(44.dp)
                    .shadow(3.dp, CircleShape)
                    .background(MobileDesign.Canvas, CircleShape)
                    .border(0.5.dp, MobileDesign.Line, CircleShape)
                    .clip(CircleShape)
                    .clickable { open = true }
                    .padding(11.dp)
                    .testTag("chat.more"),
            )
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                if (onRename != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_rename_session)) }, onClick = { open = false; onRename() })
                }
                if (onOpenProject != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_project_changes)) }, onClick = { open = false; onOpenProject() })
                }
                if (onOpenFeed != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.sessions_pending)) }, onClick = { open = false; onOpenFeed() })
                }
                if (onOpenTiming != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_run_time)) }, onClick = { open = false; onOpenTiming() })
                }
                if (onRefresh != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.common_refresh)) }, onClick = { open = false; onRefresh() })
                }
                if (onSoftStop != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_stop)) }, onClick = { open = false; onSoftStop() })
                }
                if (onForceStop != null) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.chat_force_stop), color = MaterialTheme.colorScheme.error) },
                        onClick = { open = false; confirmForceStop = true },
                    )
                }
            }
        }
    }
    if (confirmForceStop && onForceStop != null) {
        AlertDialog(
            onDismissRequest = { confirmForceStop = false },
            title = { Text(stringResource(R.string.chat_force_stop_title), color = MobileDesign.Ink) },
            text = { Text(stringResource(R.string.chat_force_stop_note), color = MobileDesign.Muted) },
            confirmButton = {
                TextButton(onClick = { confirmForceStop = false; onForceStop() }) {
                    Text(stringResource(R.string.chat_force_stop), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmForceStop = false }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ConversationTimeline(
    state: ConversationUi,
    modifier: Modifier = Modifier,
    /** A lost link is shown in the status bar, not as a row in the transcript. */
    offline: Boolean = false,
    onOpenImage: ((com.cmuxremote.mobile.data.ImageReference) -> Unit)? = null,
    onAnswerQuestion: ((String, List<String>) -> Unit)? = null,
    onOpenDetail: ((String, String) -> Unit)? = null,
    onOpenReference: ((String) -> Unit)? = null,
    /** Opens the whole group, not just its newest slice. */
    onOpenGroup: ((List<ChatMessage>) -> Unit)? = null,
    onOpenTask: ((com.cmuxremote.mobile.data.BackgroundTaskInfo) -> Unit)? = null,
    /** `true` is the reader's own pull; it bypasses the page's belief that nothing is left. */
    onLoadOlder: ((Boolean) -> Unit)? = null,
    /** A pull when there is no earlier page to ask for: read the newest page again. */
    onRefreshConversation: (() -> Unit)? = null,
    onCopyText: ((String) -> Unit)? = null,
    onShareText: ((String) -> Unit)? = null,
    onQuote: ((String) -> Unit)? = null,
    onSelectText: ((String) -> Unit)? = null,
    /** A Feed reply is in flight; every question form must stay disabled. */
    feedBusy: Boolean = false,
) {
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val atLatest by remember { derivedStateOf {
        val layout = listState.layoutInfo
        val last = layout.visibleItemsInfo.lastOrNull() ?: return@derivedStateOf true
        last.index >= layout.totalItemsCount - 1 && last.offset + last.size <= layout.viewportEndOffset + 8
    } }
    val previousCount = remember { intArrayOf(0) }
    val previousText = remember { intArrayOf(0) }
    val previousGeneration = remember { arrayOfNulls<String>(1) }
    // The last message's text grows while the agent streams; the size alone never
    // changes then, so it must be part of what re-triggers the follow scroll.
    val streaming = (state.messages.lastOrNull()?.text?.length ?: 0) + (state.preview?.length ?: 0)
    LaunchedEffect(state.messages.size, streaming, state.generation) {
        val firstLayout = previousCount[0] == 0
        val grew = state.messages.size > previousCount[0]
        val textGrew = streaming > previousText[0]
        // A replaced transcript is a different list; a reader who was at the
        // latest message is taken to the new latest one.
        val replaced = state.generation != previousGeneration[0]
        if (state.messages.isNotEmpty() &&
            (firstLayout || ((grew || textGrew) && atLatest) || (replaced && atLatest))
        ) {
            // The list includes the older-page row, images and the running footer;
            // the message index is not the last item index.
            androidx.compose.runtime.withFrameNanos { }
            val lastItem = listState.layoutInfo.totalItemsCount - 1
            if (lastItem >= 0) listState.scrollToItem(lastItem)
        }
        previousCount[0] = state.messages.size
        previousText[0] = streaming
        previousGeneration[0] = state.generation
    }
    // Prepending an earlier page must keep the row the reader was looking at in
    // place; scrolling by the raw item count jumps to a different message.
    var previousFirst by remember { mutableStateOf<String?>(null) }
    val currentFirst = state.messages.firstOrNull()?.id
    LaunchedEffect(currentFirst) {
        val anchor = previousFirst
        if (anchor != null && anchor != currentFirst) {
            val index = timelineEntries(state.messages).indexOfFirst { it.key == anchor }
            if (index >= 0) listState.scrollToItem(index)
        }
        previousFirst = currentFirst
    }
    val firstVisible = listState.firstVisibleItemIndex
    // The generation is part of the key: a read that replaced the page while the
    // reader was at the top must be able to fetch earlier messages again.
    LaunchedEffect(firstVisible, state.generation, state.hasMore) {
        if (firstVisible <= 1 && state.hasMore && !state.loadingOlder) onLoadOlder?.invoke(false)
    }
    // Expanding a card changes the height above the reader's position. Capture the
    // first visible row and restore it after the new layout lands.
    val holdPlace: () -> Unit = {
        val index = listState.firstVisibleItemIndex
        val offset = listState.firstVisibleItemScrollOffset
        scope.launch {
            androidx.compose.runtime.withFrameNanos { }
            androidx.compose.runtime.withFrameNanos { }
            runCatching { listState.scrollToItem(index, offset) }
        }
    }
    // The pull is the reader asking, not the system's refresh control: the page's
    // own top row carries the spinner, so this container draws no second one.
    val pull: () -> Unit = {
        if (state.hasMore) onLoadOlder?.invoke(true) else onRefreshConversation?.invoke()
    }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    Box(
        modifier
            .fillMaxWidth()
            // A tap on blank timeline space puts the keyboard away; a row's own tap
            // is consumed by that row first.
            .pointerInput(Unit) { detectTapGestures { keyboard?.hide() } },
    ) {
    PullToRefreshBox(
        isRefreshing = state.loadingOlder,
        onRefresh = pull,
        modifier = Modifier.fillMaxSize(),
        indicator = {},
    ) {
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
        // A short conversation sits at the bottom, next to the composer, as on the
        // iPhone; a long one scrolls normally.
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.Bottom),
    ) {
        // A prompt that is still being sent stays pinned at the top, so the reply
        // that grows underneath it never pushes it out of view.
        if (state.outgoing != null) {
            stickyHeader(key = "pinned-outgoing") {
                Column(
                    Modifier.fillMaxWidth().background(MobileDesign.Canvas),
                    horizontalAlignment = Alignment.End,
                ) {
                    UserBubble(displayedPrompt(state.outgoing))
                    Text(
                        text = when {
                            state.outgoingFailed -> stringResource(R.string.chat_outgoing_failed)
                            state.outgoingUnconfirmed -> stringResource(R.string.chat_outgoing_unconfirmed)
                            state.sending -> stringResource(R.string.chat_outgoing_sending)
                            else -> stringResource(R.string.chat_outgoing_sent)
                        },
                        color = if (state.outgoingFailed) MaterialTheme.colorScheme.error else MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(top = 4.dp, end = 6.dp),
                    )
                }
            }
        }
        if (state.loading && state.messages.isEmpty()) {
            item {
                Column(
                    Modifier.fillMaxWidth().padding(top = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    WorkingIndicator()
                    Text(stringResource(R.string.chat_loading), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        if (!state.loading && state.messages.isEmpty() && state.error == null) {
            item {
                Column(
                    Modifier.fillMaxWidth().padding(top = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Rounded.ChatBubbleOutline, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(28.dp))
                    Text(stringResource(R.string.chat_start_conversation), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        if (state.hasMore) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        // A short conversation whose groups fit on one screen cannot be
                        // scrolled, so the row itself is the way to ask for an older page.
                        .clickable(enabled = !state.loadingOlder && onLoadOlder != null) { onLoadOlder?.invoke(true) }
                        .padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                ) {
                    if (state.loadingOlder) WorkingIndicator(size = 14.dp)
                    else Text(stringResource(R.string.chat_load_older), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        items(timelineEntries(state.messages), key = { it.key }) { entry ->
            when (entry) {
                is TimelineEntry.Single -> Column(
                    modifier = Modifier.testTag("message." + entry.message.id),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    // The reply being written carries the same timer as the composer row.
                    val lastReply = state.messages.lastOrNull { it.kind == "prose" && it.role != "user" }
                    if (state.session.working && state.turnStartedAt != null && entry.message.id == lastReply?.id) {
                        LiveRunLabel(since = state.turnStartedAt, compacting = state.compacting)
                        HorizontalDivider(color = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.1f), thickness = 0.5.dp)
                    }
                    when {
                        entry.message.kind == "prose" && entry.message.role == "user" ->
                            UserBubble(displayedPrompt(entry.message.text), onCopyText, onSelectText)
                        // Markdown text is already selectable in place; a second long-press
                        // menu on top of the platform's selection menu would fight it.
                        entry.message.kind == "prose" || entry.message.kind == "thought" ->
                            MarkdownText(entry.message.text)
                        entry.message.kind == "question" -> {
                            val prompt = entry.message.prompt ?: entry.message.text
                            val request = state.feed.firstOrNull { item ->
                                item.pending && item.questions.any { it.prompt == prompt }
                            }
                            if (request != null) {
                                // A request can carry several questions; the card collects
                                // one answer per question, exactly as the Feed page does.
                                QuestionFormCard(
                                    questions = request.questions.map { question ->
                                        FeedQuestionForm(
                                            header = question.header,
                                            prompt = question.prompt,
                                            options = question.optionDetails
                                                .ifEmpty {
                                                    question.options.mapIndexed { index, label ->
                                                        com.cmuxremote.mobile.data.FeedOption(index.toString(), label, null)
                                                    }
                                                }
                                                .map { FeedQuestionOption(it.id, it.label, it.description) },
                                            multiSelect = question.multiSelect,
                                            allowCustom = question.allowCustom,
                                            allowSkip = question.allowSkip,
                                        )
                                    },
                                    busy = feedBusy,
                                    answered = null,
                                    tag = "chat.question." + entry.message.id,
                                    onSubmit = { labels -> onAnswerQuestion?.invoke(entry.message.id, labels) },
                                )
                            } else {
                                QuestionCard(
                                    prompt,
                                    entry.message.options,
                                    entry.message.selectedOption,
                                    onAnswer = onAnswerQuestion?.let { answer ->
                                        { labels -> answer(entry.message.id, labels) }
                                    },
                                )
                            }
                        }
                        else -> MessageRow(entry.message)
                    }
                    // Images belong to the message that produced them, not to the
                    // bottom of the transcript.
                    MessageImages(
                        references = state.images.filter { it.messageID == entry.message.id },
                        onOpenImage = onOpenImage,
                    )
                    // Every completed reply carries its own duration and actions,
                    // not only the last one on the page.
                    if (entry.message.kind == "prose" && entry.message.role != "user") {
                        val response = state.responses.lastOrNull { it.lastMessageID == entry.message.id }
                        if (response != null && !state.session.working) {
                            if (response.durationSeconds != null) {
                                ResponseRunLabel(
                                    seconds = response.durationSeconds,
                                    recorded = response.recordedDuration,
                                )
                            }
                            if (onQuote != null) {
                                ResponseFooter(
                                    completedAt = response.completedAt,
                                    onCopy = { onCopyText?.invoke(entry.message.text) },
                                    onShare = { onShareText?.invoke(entry.message.text) },
                                    onQuote = { onQuote?.invoke(entry.message.text) },
                                    onSelectText = { onSelectText?.invoke(entry.message.text) },
                                )
                            }
                        }
                    }
                }
                is TimelineEntry.Group -> {
                    val models = toolRowModels(entry.rows)
                    ActivityGroupCard(
                        rows = models,
                        isLatest = entry.isLatest,
                        onOpenFull = { onOpenGroup?.invoke(entry.rows) },
                        onOpenDetail = { row ->
                            onOpenDetail?.invoke(row.id, if (row.kind == "file_edit") "diff" else "output")
                        },
                        onOpenReference = onOpenReference,
                        onHoldPlace = holdPlace,
                    )
                }
            }
        }
        val knownMessages = state.messages.map { it.id }.toSet()
        val looseImages = state.images.filter { it.messageID !in knownMessages }
        if (looseImages.isNotEmpty()) {
            item(key = "loose-images") { MessageImages(looseImages, onOpenImage) }
        }
        if (state.clipped) {
            item(key = "clipped") {
                Text(
                    stringResource(R.string.chat_history_clipped),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
        if (state.preview != null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.chat_live_preview), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    Text(state.preview, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        if (state.session.working) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WorkingIndicator()
                    if (state.turnStartedAt != null) {
                        LiveRunLabel(since = state.turnStartedAt, compacting = state.compacting)
                    } else {
                        Text(stringResource(R.string.common_working), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    }
                    if (state.stopRequested) {
                        Text(stringResource(R.string.chat_stop_requested), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = state.session.agent.replaceFirstChar { it.uppercase() },
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
        // A lost link belongs to the status bar; the page keeps only its own errors.
        if (state.error != null && !offline) {
            item {
                Text(state.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    }
    if (!atLatest && state.messages.isNotEmpty()) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp)
                .size(44.dp)
                .shadow(3.dp, CircleShape)
                .background(MobileDesign.Canvas, CircleShape)
                .border(0.5.dp, MobileDesign.Line, CircleShape)
                .clickable {
                    com.cmuxremote.mobile.data.Diagnostics.log(
                        com.cmuxremote.mobile.data.Diagnostics.Level.Debug,
                        "scroll",
                        "jump to latest",
                    )
                    scope.launch {
                        val last = listState.layoutInfo.totalItemsCount - 1
                        if (last >= 0) listState.animateScrollToItem(last)
                    }
                }
                .testTag("chat.latest"),
            contentAlignment = Alignment.Center,
        ) {
            Text("↓", fontSize = 20.sp, color = MobileDesign.Ink)
        }
    }
    }
}

/** One timeline row: a message on its own, or a run of tool operations. */
private sealed interface TimelineEntry {
    val key: String
    data class Single(val message: ChatMessage) : TimelineEntry { override val key = message.id }
    data class Group(val rows: List<ChatMessage>, val isLatest: Boolean) : TimelineEntry {
        // Keyed by its newest row: an earlier page prepended above must not change the
        // group's identity, or the list loses the reader's place when the page grows.
        override val key = "group-" + (rows.lastOrNull()?.id ?: "")
    }
}

/** Consecutive tool operations collapse into one group, as they do on the iPhone. */
private fun timelineEntries(messages: List<ChatMessage>): List<TimelineEntry> {
    val out = mutableListOf<TimelineEntry>()
    var run = mutableListOf<ChatMessage>()
    fun flush(latest: Boolean) {
        if (run.isEmpty()) return
        out += TimelineEntry.Group(run.toList(), latest)
        run = mutableListOf()
    }
    messages.forEachIndexed { index, message ->
        val isOperation = message.kind == "tool_use" || message.kind == "terminal" || message.kind == "file_edit"
        if (isOperation) {
            run += message
        } else {
            flush(latest = false)
            out += TimelineEntry.Single(message)
        }
        if (index == messages.lastIndex) flush(latest = true)
    }
    return out
}

@Composable
private fun MessageRow(message: ChatMessage) {
    when {
        message.kind == "prose" && message.role == "user" -> UserBubble(message.text)
        message.kind == "prose" || message.kind == "thought" ->
            Text(message.text, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyLarge)
        message.kind == "tool_use" -> ToolRow(
            title = message.toolName ?: message.text.ifBlank { stringResource(R.string.chat_tool_call) },
            status = message.status,
        )
        message.kind == "terminal" -> CodeCard(title = message.text.ifBlank { stringResource(R.string.chat_command) }, body = null)
        message.kind == "file_edit" -> CodeCard(title = message.filePath ?: stringResource(R.string.chat_file_change), body = message.diff)
        message.kind == "question" -> QuestionCard(prompt = message.prompt ?: message.text, options = message.options, selected = message.selectedOption)
        message.kind == "permission_request" -> ToolRow(
            title = message.text.ifBlank { stringResource(R.string.chat_needs_approval) },
            status = stringResource(R.string.chat_waiting),
        )
        message.kind == "attachment" -> Text(
            message.text.ifBlank { stringResource(R.string.chat_image_attachment) },
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.labelMedium,
        )
        message.kind == "status" -> Text(message.text, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        else -> Text(
            message.text.ifBlank { stringResource(R.string.chat_unsupported_message) },
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun UserBubble(
    text: String,
    onCopy: ((String) -> Unit)? = null,
    onSelect: ((String) -> Unit)? = null,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        LongPressText(text = text, onCopy = onCopy, onSelect = onSelect) {
            Surface(
                color = MobileDesign.AccentSoft,
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier.widthIn(max = 320.dp),
            ) {
                Text(
                    text = text,
                    color = MobileDesign.Accent,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp),
                )
            }
        }
    }
}

/**
 * Long-press actions for a block of text: copy all of it, or open it on a page
 * where a part can be selected. This is the iPhone's context menu on Android.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LongPressText(
    text: String,
    onCopy: ((String) -> Unit)?,
    onSelect: ((String) -> Unit)?,
    content: @Composable () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val available = onCopy != null || onSelect != null
    Box {
        Box(
            Modifier.combinedClickable(
                onClick = {},
                onLongClick = if (available) ({ open = true }) else null,
            ),
        ) { content() }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (onCopy != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.chat_copy_text)) },
                    onClick = { open = false; onCopy(text) },
                )
            }
            if (onSelect != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.common_select_text)) },
                    onClick = { open = false; onSelect(text) },
                )
            }
        }
    }
}

/** "退出码 0 · 1.2s", only for the fields the transcript actually recorded. */
@Composable
internal fun terminalMeta(exitCode: Int?, durationSeconds: Double?): String? {
    val parts = buildList {
        exitCode?.let { add(stringResource(R.string.chat_exit_code, it)) }
        durationSeconds?.let {
            add(stringResource(R.string.chat_elapsed, String.format(java.util.Locale.getDefault(), "%.1fs", it)))
        }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

@Composable
private fun ToolRow(title: String, status: String?) {
    Row(
        modifier = Modifier.fillMaxWidth().background(MobileDesign.Soft, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Rounded.Book, null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
        Text(title, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (status != null) {
            Text(status, color = if (status == "failed") MaterialTheme.colorScheme.error else MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        Icon(Icons.Rounded.ChevronRight, null, tint = MobileDesign.Muted, modifier = Modifier.size(15.dp))
    }
}

@Composable
private fun CodeCard(title: String, body: String?) {
    Column(Modifier.fillMaxWidth().background(MobileDesign.Soft, RoundedCornerShape(14.dp)).padding(12.dp)) {
        Text(title, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (!body.isNullOrBlank()) {
            Spacer(Modifier.height(8.dp))
            Text(
                body,
                color = MobileDesign.Ink,
                fontFamily = FontFamily.Monospace,
                fontSize = 12.sp,
                lineHeight = 18.sp,
                maxLines = 12,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * A send whose reply was lost. It is never replayed: the reader can ask the Mac
 * what became of it, or mark that they already looked there.
 */
@Composable
private fun PendingSendBanner(
    onCheck: (() -> Unit)?,
    onAcknowledge: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MobileDesign.Soft, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = stringResource(R.string.chat_pending_send_title),
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
        )
        Text(
            text = stringResource(R.string.chat_pending_send_note),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.labelMedium,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (onCheck != null) {
                Text(
                    text = stringResource(R.string.chat_check_receipt),
                    color = MobileDesign.Accent,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.clickable(onClick = onCheck).padding(vertical = 4.dp),
                )
            }
            if (onAcknowledge != null) {
                Text(
                    text = stringResource(R.string.chat_pending_send_acknowledge),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.clickable(onClick = onAcknowledge).padding(vertical = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun QuestionCard(
    prompt: String,
    options: List<String>,
    selected: String?,
    onAnswer: ((List<String>) -> Unit)? = null,
) {
    com.cmuxremote.mobile.ui.components.FloatingSurface(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(prompt.ifBlank { stringResource(R.string.chat_agent_question) }, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        options.forEach { option ->
            Text(
                text = if (option == selected) "✓ $option" else option,
                color = if (option == selected) MobileDesign.Accent else if (onAnswer != null) MobileDesign.Ink else MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                modifier = if (onAnswer != null && selected == null) {
                    Modifier
                        .fillMaxWidth()
                        .clickable { onAnswer(listOf(option)) }
                        .padding(vertical = 4.dp)
                } else Modifier,
            )
        }
        if (selected == null && options.isEmpty()) {
            Text(stringResource(R.string.chat_answer_in_pending), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        } else if (selected == null && onAnswer == null) {
            // The request expired or was answered elsewhere; the card is now a record.
            Text(stringResource(R.string.chat_question_unavailable), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        }
    }
}

@Composable
fun ComposerArea(
    draft: String,
    onDraftChange: (String) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    working: Boolean,
    canSend: Boolean,
    sending: Boolean,
    hasBackgroundTasks: Boolean,
    error: String?,
    modifier: Modifier = Modifier,
    /** A prepared image counts as a draft even when the text is empty. */
    hasImages: Boolean = false,
    onPickImages: (() -> Unit)? = null,
    onPickImageFile: (() -> Unit)? = null,
    onOpenProject: (() -> Unit)? = null,
    onOpenFeed: (() -> Unit)? = null,
    dictating: Boolean = false,
    onToggleVoice: (() -> Unit)? = null,
    voiceError: String? = null,
) {
    var focused by remember { mutableStateOf(false) }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(MobileDesign.Canvas.copy(alpha = 0.88f), MobileDesign.Canvas.copy(alpha = 0.98f)),
                ),
            )
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (hasBackgroundTasks) {
            Row(
                modifier = Modifier.background(MobileDesign.Soft, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                WorkingIndicator(size = 11.dp)
                Text(stringResource(R.string.chat_background_tasks_running), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
            }
        }
        if (!canSend) {
            Text(stringResource(R.string.chat_read_only_notice), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
            return@Column
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(6.dp, CircleShape, clip = false)
                .background(MobileDesign.Canvas, CircleShape)
                .border(0.5.dp, MobileDesign.Line, CircleShape)
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box {
                var actions by remember { mutableStateOf(false) }
                val hasActions = onPickImages != null || onPickImageFile != null || onOpenProject != null || onOpenFeed != null
                Box(
                    modifier = Modifier.size(40.dp).clickable(enabled = hasActions) { actions = true },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Rounded.Add,
                        contentDescription = stringResource(R.string.chat_add_attachment),
                        tint = if (hasActions) MobileDesign.Ink else MobileDesign.Muted,
                        modifier = Modifier.size(20.dp),
                    )
                }
                DropdownMenu(expanded = actions, onDismissRequest = { actions = false }) {
                    if (onPickImages != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_add_photo)) },
                            onClick = { actions = false; onPickImages() },
                        )
                    }
                    if (onPickImageFile != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_add_image_file)) },
                            onClick = { actions = false; onPickImageFile() },
                        )
                    }
                    if (onOpenProject != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_project_changes)) },
                            onClick = { actions = false; onOpenProject() },
                        )
                    }
                    if (onOpenFeed != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.sessions_pending)) },
                            onClick = { actions = false; onOpenFeed() },
                        )
                    }
                }
            }
            BasicTextField(
                value = draft,
                onValueChange = onDraftChange,
                modifier = Modifier
                    .weight(1f)
                    .testTag("chat.composer")
                    .onFocusChanged { focused = it.isFocused },
                textStyle = TextStyle(color = MobileDesign.Ink, fontSize = 15.sp),
                cursorBrush = SolidColor(MobileDesign.Accent),
                maxLines = if (focused) 8 else 4,
                decorationBox = { inner ->
                    Box {
                        if (draft.isEmpty()) Text(stringResource(R.string.chat_input_placeholder), color = MobileDesign.Muted, fontSize = 15.sp)
                        inner()
                    }
                },
            )
            Box(
                modifier = Modifier.size(40.dp).clickable(enabled = onToggleVoice != null) { onToggleVoice?.invoke() },
                contentAlignment = Alignment.Center,
            ) {
            Icon(
                Icons.Rounded.Mic,
                contentDescription = if (dictating) stringResource(R.string.chat_end_dictation)
                else stringResource(R.string.chat_voice_input),
                tint = when {
                    dictating -> MobileDesign.Accent
                    onToggleVoice != null -> MobileDesign.Ink
                    else -> MobileDesign.Muted
                },
                modifier = Modifier.size(20.dp),
            )
            }
            if (working && draft.isBlank()) {
                Box(
                    modifier = Modifier.size(40.dp).clip(CircleShape).background(MobileDesign.Accent).clickable(onClick = onStop).testTag("chat.stop"),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Stop, contentDescription = stringResource(R.string.chat_stop), tint = MobileDesign.Canvas, modifier = Modifier.size(16.dp))
                }
            } else {
                // A prepared image is a draft of its own; text is optional.
                val enabled = (draft.isNotBlank() || hasImages) && !sending
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(if (enabled) MobileDesign.Accent else MaterialTheme.colorScheme.surfaceVariant)
                        .clickable(enabled = enabled, onClick = onSend)
                        .testTag("chat.send"),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Rounded.ArrowUpward,
                        contentDescription = stringResource(R.string.chat_send),
                        tint = if (enabled) MobileDesign.Canvas else MobileDesign.Muted,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
        if (error != null) {
            Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
        }
        if (voiceError != null) {
            Text(voiceError, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
        }
    }
}

/**
 * The recorded prompt without the `<pasted_content>` wrapper the terminal adds
 * around a long paste. The reader's own bubble should show what they typed.
 */
internal fun displayedPrompt(text: String): String {
    if (!text.contains("<pasted_content")) return text
    val opening = Regex("""<pasted_content id="[^"<>\n]{0,64}">\n?""")
    val closing = Regex("""\n?</pasted_content(?: id="[^"<>\n]{0,64}")?>""")
    val unwrapped = text.replace(opening, "").replace(closing, "")
    // Only a wrapped prompt is trimmed, so an ordinary message keeps its spacing.
    return if (unwrapped == text) text else unwrapped.trim()
}

/** Recorded images under the message that carried them. */
@Composable
private fun MessageImages(
    references: List<com.cmuxremote.mobile.data.ImageReference>,
    onOpenImage: ((com.cmuxremote.mobile.data.ImageReference) -> Unit)?,
) {
    if (references.isEmpty() || onOpenImage == null) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        references.forEach { reference ->
            Text(
                text = stringResource(
                    R.string.chat_view_image,
                    reference.name.ifBlank { stringResource(R.string.chat_image_record) },
                ),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier
                    .background(MobileDesign.AccentSoft, RoundedCornerShape(50))
                    .clickable { onOpenImage(reference) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
    }
}

/** Dictation has its own draft: finishing, cancelling and using are explicit. */
@Composable
private fun SpeechDraftStrip(
    text: String,
    listening: Boolean,
    onFinish: (() -> Unit)?,
    onUse: (() -> Unit)?,
    onCancel: (() -> Unit)?,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp)
            .background(MobileDesign.Soft, RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (listening) WorkingIndicator(size = 12.dp)
            Text(
                text = stringResource(if (listening) R.string.chat_speech_listening else R.string.chat_speech_draft),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
            if (onCancel != null) {
                Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, modifier = Modifier.clickable { onCancel() }.padding(4.dp))
            }
            if (listening && onFinish != null) {
                Text(stringResource(R.string.chat_speech_finish), color = MobileDesign.Accent, style = MaterialTheme.typography.labelMedium, modifier = Modifier.clickable { onFinish() }.padding(4.dp))
            } else if (!listening && onUse != null && text.isNotBlank()) {
                Text(stringResource(R.string.chat_speech_use), color = MobileDesign.Accent, style = MaterialTheme.typography.labelMedium, modifier = Modifier.clickable { onUse() }.padding(4.dp))
            }
        }
        if (text.isNotBlank()) {
            Text(text, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
