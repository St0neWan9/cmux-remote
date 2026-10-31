package com.cmuxremote.mobile.ui

import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
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
    onOpenProject: (() -> Unit)? = null,
    onOpenTiming: (() -> Unit)? = null,
    onOpenImage: ((com.cmuxremote.mobile.data.ImageReference) -> Unit)? = null,
    onAnswerQuestion: ((String, List<String>) -> Unit)? = null,
    onOpenDetail: ((String, String) -> Unit)? = null,
    onOpenReference: ((String) -> Unit)? = null,
    onOpenTask: ((com.cmuxremote.mobile.data.BackgroundTaskInfo) -> Unit)? = null,
    onLoadOlder: (() -> Unit)? = null,
    pendingImages: List<Pair<String, String>> = emptyList(),
    onRemoveImage: (Int) -> Unit = {},
    onPickImages: (() -> Unit)? = null,
    dictating: Boolean = false,
    onToggleVoice: (() -> Unit)? = null,
    voiceError: String? = null,
    onForceStop: (() -> Unit)? = null,
    pendingSend: Boolean = false,
    onCheckPending: (() -> Unit)? = null,
    onAcknowledgePending: (() -> Unit)? = null,
    offline: Boolean = false,
    onRetryConnection: (() -> Unit)? = null,
    onPickImageFile: (() -> Unit)? = null,
    onOpenFeed: (() -> Unit)? = null,
) {
    var renaming by remember { mutableStateOf(false) }
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        ConversationHeader(
            title = state.session.title,
            subtitle = subtitle(state.session, state.agentModel, LocalContext.current),
            onBack = onBack,
            models = models,
            currentModel = state.agentModel,
            canSwitchModel = state.session.writable && !state.session.working,
            onSwitchModel = onSwitchModel,
            onRename = { renaming = true },
            onOpenProject = onOpenProject,
            onOpenTiming = onOpenTiming,
            onForceStop = onForceStop?.takeIf { state.session.working },
            onSoftStop = if (state.session.working) onStop else null,
        )
        if (offline) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.errorContainer)
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = stringResource(R.string.chat_connection_lost),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.weight(1f),
                )
                if (onRetryConnection != null) {
                    Text(
                        text = stringResource(R.string.common_retry),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.clickable(onClick = onRetryConnection).padding(vertical = 4.dp),
                    )
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
            onLoadOlder = onLoadOlder,
            onCopyText = onCopyText,
            onShareText = onShareText,
            onQuote = onQuote,
            onSelectText = onSelectText,
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
        if (pendingImages.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                pendingImages.forEachIndexed { index, (name, base64) ->
                    Box(
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(MobileDesign.Soft),
                    ) {
                        val bitmap = remember(base64) {
                            runCatching {
                                val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
                                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            }.getOrNull()
                        }
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
        ComposerArea(
            draft = state.draft,
            onDraftChange = onDraft,
            onSend = onSend,
            onStop = onStop,
            working = state.session.working,
            canSend = state.session.writable,
            sending = state.sending,
            hasBackgroundTasks = state.messages.any { it.kind == "tool_use" && it.status == "running" },
            error = if (offline) null else state.error,
            onPickImages = onPickImages,
            onPickImageFile = onPickImageFile,
            onOpenProject = onOpenProject,
            onOpenFeed = onOpenFeed,
            dictating = dictating,
            onToggleVoice = onToggleVoice,
            voiceError = voiceError,
        )
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

private fun subtitle(session: SessionDescriptor, agentModel: String?, context: Context): String =
    listOf(
        session.agent.replaceFirstChar { it.uppercase() },
        agentModel ?: "",
        session.workspaceID?.take(8) ?: "",
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
    onOpenTiming: (() -> Unit)? = null,
    onForceStop: (() -> Unit)? = null,
    onSoftStop: (() -> Unit)? = null,
) {
    var confirmForceStop by remember { mutableStateOf(false) }
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (onBack != null) {
            Box(
                modifier = Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onBack),
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
                modifier = Modifier.size(20.dp).clickable { open = true },
            )
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                if (onRename != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_rename_session)) }, onClick = { open = false; onRename() })
                }
                if (onOpenProject != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_project_changes)) }, onClick = { open = false; onOpenProject() })
                }
                if (onOpenTiming != null) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.chat_run_time)) }, onClick = { open = false; onOpenTiming() })
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
    onOpenTask: ((com.cmuxremote.mobile.data.BackgroundTaskInfo) -> Unit)? = null,
    onLoadOlder: (() -> Unit)? = null,
    onCopyText: ((String) -> Unit)? = null,
    onShareText: ((String) -> Unit)? = null,
    onQuote: ((String) -> Unit)? = null,
    onSelectText: ((String) -> Unit)? = null,
) {
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val atLatest by remember { derivedStateOf {
        val layout = listState.layoutInfo
        val last = layout.visibleItemsInfo.lastOrNull() ?: return@derivedStateOf true
        last.index >= layout.totalItemsCount - 1 && last.offset + last.size <= layout.viewportEndOffset + 8
    } }
    val previousCount = remember { intArrayOf(0) }
    val previousGeneration = remember { arrayOfNulls<String>(1) }
    LaunchedEffect(state.messages.size, state.generation) {
        val firstLayout = previousCount[0] == 0
        val grew = state.messages.size > previousCount[0]
        // A replaced transcript is a different list; a reader who was at the
        // latest message is taken to the new latest one.
        val replaced = state.generation != previousGeneration[0]
        if (state.messages.isNotEmpty() && (firstLayout || (grew && atLatest) || (replaced && atLatest))) {
            listState.scrollToItem(state.messages.size - 1)
        }
        previousCount[0] = state.messages.size
        previousGeneration[0] = state.generation
    }
    val firstVisible = listState.firstVisibleItemIndex
    // The generation is part of the key: a read that replaced the page while the
    // reader was at the top must be able to fetch earlier messages again.
    LaunchedEffect(firstVisible, state.generation, state.hasMore) {
        if (firstVisible <= 1 && state.hasMore && !state.loadingOlder) onLoadOlder?.invoke()
    }
    Box(modifier.fillMaxWidth()) {
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.loading && state.messages.isEmpty()) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    WorkingIndicator()
                }
            }
        }
        if (!state.loading && state.messages.isEmpty() && state.error == null) {
            item {
                Text(stringResource(R.string.chat_no_messages), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (state.hasMore) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        // A short conversation whose groups fit on one screen cannot be
                        // scrolled, so the row itself is the way to ask for an older page.
                        .clickable(enabled = !state.loadingOlder && onLoadOlder != null) { onLoadOlder?.invoke() }
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
                is TimelineEntry.Single -> when {
                    entry.message.kind == "prose" && entry.message.role == "user" ->
                        UserBubble(entry.message.text, onCopyText, onSelectText)
                    // Markdown text is already selectable in place; a second long-press
                    // menu on top of the platform's selection menu would fight it.
                    entry.message.kind == "prose" || entry.message.kind == "thought" ->
                        MarkdownText(entry.message.text)
                    entry.message.kind == "question" -> QuestionCard(
                        entry.message.prompt ?: entry.message.text,
                        entry.message.options,
                        entry.message.selectedOption,
                        onAnswer = onAnswerQuestion?.let { answer ->
                            { labels -> answer(entry.message.id, labels) }
                        },
                    )
                    else -> MessageRow(entry.message)
                }
                is TimelineEntry.Group -> {
                    val models = entry.rows.map { message: ChatMessage ->
                        ToolRowModel(
                            id = message.id,
                            kind = message.kind,
                            title = message.filePath ?: message.toolName ?: message.command
                                ?: message.text.ifBlank { stringResource(R.string.chat_operation) },
                            status = message.status,
                            input = message.inputDetail,
                            output = message.output,
                            diff = message.diff,
                            canOpenDetail = message.kind == "tool_use" || message.kind == "file_edit",
                            references = message.references,
                            meta = terminalMeta(message.exitCode, message.durationSeconds),
                        )
                    }
                    ActivityGroupCard(
                        rows = models,
                        isLatest = entry.isLatest,
                        onOpenFull = { onOpenDetail?.invoke(entry.rows.last().id, "output") },
                        onOpenDetail = { row ->
                            onOpenDetail?.invoke(row.id, if (row.kind == "file_edit") "diff" else "output")
                        },
                        onOpenReference = onOpenReference,
                    )
                }
            }
        }
        if (state.outgoing != null) {
            item(key = "outgoing") {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
                    UserBubble(state.outgoing)
                    Text(
                        text = when {
                            state.outgoingFailed -> stringResource(R.string.chat_outgoing_failed)
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
        if (state.images.isNotEmpty() && onOpenImage != null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    state.images.forEach { reference ->
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
        }
        if (state.preview != null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.chat_live_preview), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    Text(state.preview, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        // A finished reply carries the iPhone's footer: its duration, then copy,
        // share, quote and select text.
        val lastProse = state.messages.lastOrNull { it.kind == "prose" && it.role != "user" }
        val lastResponse = lastProse?.let { prose ->
            state.responses.lastOrNull { it.lastMessageID == prose.id }
        }
        if (lastProse != null && !state.session.working) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (lastResponse?.durationSeconds != null) {
                        ResponseRunLabel(
                            seconds = lastResponse.durationSeconds,
                            recorded = lastResponse.recordedDuration,
                        )
                    }
                    if (onQuote != null) {
                        ResponseFooter(
                            completedAt = lastResponse?.completedAt,
                            onCopy = { onCopyText?.invoke(lastProse.text) },
                            onShare = { onShareText?.invoke(lastProse.text) },
                            onQuote = { onQuote?.invoke(lastProse.text) },
                            onSelectText = { onSelectText?.invoke(lastProse.text) },
                        )
                    }
                }
            }
        }
        if (state.session.working) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WorkingIndicator()
                    if (state.turnStartedAt != null) {
                        LiveRunLabel(since = state.turnStartedAt, compacting = false)
                    } else {
                        Text(stringResource(R.string.common_working), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    }
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
    if (!atLatest && state.messages.isNotEmpty()) {
        FloatingActionButton(
            onClick = { scope.launch { listState.animateScrollToItem((state.messages.size - 1).coerceAtLeast(0)) } },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            containerColor = MobileDesign.Canvas,
            contentColor = MobileDesign.Ink,
            shape = CircleShape,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 3.dp),
        ) {
            Text("↓", fontSize = 22.sp, color = MobileDesign.Ink)
        }
    }
    }
}

/** One timeline row: a message on its own, or a run of tool operations. */
private sealed interface TimelineEntry {
    val key: String
    data class Single(val message: ChatMessage) : TimelineEntry { override val key = message.id }
    data class Group(val rows: List<ChatMessage>, val isLatest: Boolean) : TimelineEntry {
        override val key = "group-" + (rows.firstOrNull()?.id ?: "")
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
private fun terminalMeta(exitCode: Int?, durationSeconds: Double?): String? {
    val parts = buildList {
        exitCode?.let { add(stringResource(R.string.chat_exit_code, it)) }
        durationSeconds?.let {
            add(stringResource(R.string.chat_elapsed, String.format(java.util.Locale.US, "%.1fs", it)))
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
    Column(
        Modifier.fillMaxWidth().background(MobileDesign.Soft, RoundedCornerShape(14.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
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
    onPickImages: (() -> Unit)? = null,
    onPickImageFile: (() -> Unit)? = null,
    onOpenProject: (() -> Unit)? = null,
    onOpenFeed: (() -> Unit)? = null,
    dictating: Boolean = false,
    onToggleVoice: (() -> Unit)? = null,
    voiceError: String? = null,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
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
            modifier = Modifier.fillMaxWidth().background(MobileDesign.Canvas, CircleShape).padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box {
                var actions by remember { mutableStateOf(false) }
                val hasActions = onPickImages != null || onPickImageFile != null || onOpenProject != null || onOpenFeed != null
                Icon(
                    Icons.Rounded.Add,
                    contentDescription = stringResource(R.string.chat_add_attachment),
                    tint = if (hasActions) MobileDesign.Ink else MobileDesign.Muted,
                    modifier = Modifier.size(20.dp).clickable(enabled = hasActions) { actions = true },
                )
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
                modifier = Modifier.weight(1f),
                textStyle = TextStyle(color = MobileDesign.Ink, fontSize = 15.sp),
                cursorBrush = SolidColor(MobileDesign.Accent),
                maxLines = 4,
                decorationBox = { inner ->
                    Box {
                        if (draft.isEmpty()) Text(stringResource(R.string.chat_input_placeholder), color = MobileDesign.Muted, fontSize = 15.sp)
                        inner()
                    }
                },
            )
            Icon(
                Icons.Rounded.Mic,
                contentDescription = if (dictating) stringResource(R.string.chat_end_dictation)
                else stringResource(R.string.chat_voice_input),
                tint = when {
                    dictating -> MobileDesign.Accent
                    onToggleVoice != null -> MobileDesign.Ink
                    else -> MobileDesign.Muted
                },
                modifier = Modifier.size(20.dp).clickable(enabled = onToggleVoice != null) { onToggleVoice?.invoke() },
            )
            if (working && draft.isBlank()) {
                Box(
                    modifier = Modifier.size(34.dp).clip(CircleShape).background(MobileDesign.Accent).clickable(onClick = onStop),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Stop, contentDescription = stringResource(R.string.chat_stop), tint = MobileDesign.Canvas, modifier = Modifier.size(16.dp))
                }
            } else {
                val enabled = draft.isNotBlank() && !sending
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(if (enabled) MobileDesign.Accent else MaterialTheme.colorScheme.surfaceVariant)
                        .clickable(enabled = enabled, onClick = onSend),
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
