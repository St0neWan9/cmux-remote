package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** A task the agent detached and has not finished. */
data class BackgroundTask(val id: String, val tool: String, val status: String, val running: Boolean)

/**
 * The detached tasks of the current conversation, as a horizontally scrolling row of
 * pill chips. A running task shows an accent spinner, a settled one a muted dot.
 */
@Composable
fun BackgroundTasksRow(
    tasks: List<BackgroundTask>,
    onOpen: (BackgroundTask) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (tasks.isEmpty()) return
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        tasks.forEach { task ->
            Row(
                modifier = Modifier
                    .background(MobileDesign.Soft, CircleShape)
                    .clickable { onOpen(task) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (task.running) {
                    WorkingIndicator(size = 10.dp)
                } else {
                    Spacer(Modifier.size(7.dp).background(MobileDesign.Muted, CircleShape))
                }
                Text(
                    text = task.tool,
                    color = MobileDesign.Ink,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * A bounded page of one task's own record: an agent's conversation, or a
 * detached command's output, paged from the beginning.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskDetailSheet(
    task: BackgroundTask,
    text: String?,
    loading: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    hasMore: Boolean = false,
    loadingMore: Boolean = false,
    onLoadMore: (() -> Unit)? = null,
    /** An Agent task's own conversation. */
    messages: List<com.cmuxremote.mobile.data.ChatMessage> = emptyList(),
    command: String? = null,
    totalBytes: Int? = null,
    running: Boolean = false,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MobileDesign.Canvas) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = task.tool,
                        color = MobileDesign.Ink,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = task.status,
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (loading) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    WorkingIndicator()
                }
            }
            if (messages.isNotEmpty()) {
                // An Agent task is a conversation; it uses the timeline's own rows
                // instead of dumping a wall of raw text.
                val rows = toolRowModels(messages)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 460.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    messages.forEachIndexed { index, message ->
                        when {
                            message.kind == "prose" && message.role == "user" ->
                                Text(message.text, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
                            message.kind == "prose" || message.kind == "thought" ->
                                com.cmuxremote.mobile.ui.markdown.MarkdownText(message.text)
                            message.kind in setOf("tool_use", "terminal", "file_edit") ->
                                ToolDisclosureRow(row = rows[index], onOpenDetail = {})
                            else -> Text(message.text, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            } else if (command != null) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.chat_background_command), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    Text(
                        command,
                        color = MobileDesign.Ink,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        modifier = Modifier.fillMaxWidth().background(MobileDesign.Code, RoundedCornerShape(10.dp)).padding(10.dp),
                    )
                }
            }
            if (text != null && text.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 420.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(MobileDesign.Code),
                ) {
                    Box(
                        Modifier
                            .verticalScroll(rememberScrollState())
                            .horizontalScroll(rememberScrollState())
                            .padding(12.dp),
                    ) {
                        SelectionContainer {
                            Text(
                                text = text,
                                color = MobileDesign.Ink,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 12.sp,
                                lineHeight = 17.sp,
                                softWrap = false,
                            )
                        }
                    }
                }
                if (hasMore && onLoadMore != null) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MobileDesign.Soft, RoundedCornerShape(50))
                            .clickable(enabled = !loadingMore, onClick = onLoadMore)
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        if (loadingMore) {
                            WorkingIndicator(size = 14.dp)
                        } else {
                            Text(stringResource(R.string.chat_load_more), color = MobileDesign.Ink, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            } else if (!loading && error == null) {
                Text(stringResource(R.string.chat_task_empty), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            }
            if (error != null) {
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
            if (running) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    WorkingIndicator(size = 12.dp)
                    Text(stringResource(R.string.chat_background_running), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.weight(1f))
                    totalBytes?.takeIf { it > 0 }?.let { bytes ->
                        Text(android.text.format.Formatter.formatShortFileSize(androidx.compose.ui.platform.LocalContext.current, bytes.toLong()), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MobileDesign.Soft)
                    .clickable(onClick = onDismiss)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.common_close), color = MobileDesign.Ink, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}
