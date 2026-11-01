package com.cmuxremote.mobile.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.Build
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** One rendered message inside an activity group. */
data class ToolRowModel(
    val id: String,
    val kind: String,          // "tool_use" | "terminal" | "file_edit"
    val title: String,         // tool name, command summary, or file path
    val status: String?,       // "succeeded" | "failed" | "running"
    val input: String?,        // code block body (tool input or "$ command")
    val output: String?,       // code block body
    val diff: String?,
    val canOpenDetail: Boolean,
    /** Files the tool input referenced, opened on the project page. */
    val references: List<String> = emptyList(),
    /** Exit code and duration of a terminal capture, when recorded. */
    val meta: String? = null,
    /** When the tool finished; shown inside its open card. */
    val completedAt: java.time.Instant? = null,
    /** Which tool ran, for the read/search icon family. */
    val toolName: String? = null,
)

/** A group longer than this draws only its newest slice; the whole turn opens on its own page. */
private const val InlineRowLimit = 6

/** Room a code block takes before it starts scrolling inside itself. */
private val CodeBlockMaxHeight = 280.dp

/** Matches the Swift tool card's surface inset. */
private val CardInset = 16.dp

/**
 * Details stay accessible behind one quiet summary instead of filling the conversation with cards.
 *
 * The newest group opens on its own so its work can be followed as it happens, and closes once the next
 * message arrives; a reader's own choice wins until the group stops being the newest.
 */
@Composable
fun ActivityGroupCard(
    rows: List<ToolRowModel>,
    isLatest: Boolean,
    onOpenFull: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenDetail: (ToolRowModel) -> Unit = {},
    onOpenReference: ((String) -> Unit)? = null,
    /** Called before an expansion, so the page can hold the reader's position. */
    onHoldPlace: (() -> Unit)? = null,
) {
    // null means "follow the newest group"; a tap records the reader's own choice.
    var choice by remember { mutableStateOf<Boolean?>(null) }
    val expanded = choice ?: isLatest
    LaunchedEffect(isLatest) {
        if (!isLatest) choice = null
    }

    // A long group draws only its newest slice here; the full page is one tap away.
    val visibleRows = if (rows.size > InlineRowLimit) rows.takeLast(InlineRowLimit) else rows

    Column(
        modifier.fillMaxWidth().animateContentSize(animationSpec = androidx.compose.animation.core.tween(180, easing = androidx.compose.animation.core.FastOutSlowInEasing)),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onHoldPlace?.invoke(); choice = !expanded }
                .padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Icon(
                Icons.Rounded.Book,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = groupLabel(rows.size),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.ChevronRight,
                contentDescription = if (expanded) stringResource(R.string.common_collapse) else stringResource(R.string.common_expand),
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
        }
        if (expanded) {
            visibleRows.forEach { row ->
                ToolDisclosureRow(
                    row = row,
                    onOpenDetail = { onOpenDetail(row) },
                    onOpenReference = onOpenReference,
                    onHoldPlace = onHoldPlace,
                )
            }
            if (rows.size > InlineRowLimit) {
                Text(
                    text = stringResource(R.string.chat_view_all_operations, rows.size),
                    color = MobileDesign.Accent,
                    style = MaterialTheme.typography.labelMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MobileDesign.AccentSoft, RoundedCornerShape(50))
                        .clickable(onClick = onOpenFull)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }
    }
}

/** Maps recorded tool messages to the rows both the inline group and its page draw. */
@Composable
fun toolRowModels(messages: List<com.cmuxremote.mobile.data.ChatMessage>): List<ToolRowModel> =
    messages.map { message ->
        ToolRowModel(
            id = message.id,
            kind = message.kind,
            title = when (message.kind) {
                "terminal" -> stringResource(R.string.tool_card_shell)
                else -> message.filePath ?: message.toolName ?: message.command
                    ?: message.text.ifBlank { stringResource(R.string.chat_operation) }
            },
            status = message.status,
            input = if (message.kind == "terminal" && !message.command.isNullOrBlank()) {
                "$ " + message.command
            } else {
                message.inputDetail
            },
            output = message.output,
            diff = message.diff,
            canOpenDetail = message.kind == "tool_use" || message.kind == "file_edit",
            references = message.references,
            meta = terminalMeta(message.exitCode, message.durationSeconds),
            completedAt = message.completedAt,
            toolName = message.toolName,
        )
    }

/**
 * The whole activity group on its own page. The inline card draws only the newest
 * slice; this page keeps every operation in the same quiet disclosure rows.
 */
@Composable
fun ActivityGroupPage(
    rows: List<ToolRowModel>,
    onOpenDetail: (ToolRowModel) -> Unit,
    onOpenReference: ((String) -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        rows.forEach { row ->
            ToolDisclosureRow(
                row = row,
                onOpenDetail = { onOpenDetail(row) },
                onOpenReference = onOpenReference,
            )
        }
    }
}

/** A quiet tool row that opens a pale code card without disclosure indentation. */
@Composable
internal fun ToolDisclosureRow(
    row: ToolRowModel,
    onOpenDetail: () -> Unit,
    onOpenReference: ((String) -> Unit)? = null,
    onHoldPlace: (() -> Unit)? = null,
) {
    var expanded by remember(row.id) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize(animationSpec = androidx.compose.animation.core.tween(180, easing = androidx.compose.animation.core.FastOutSlowInEasing)), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onHoldPlace?.invoke(); expanded = !expanded }
                .padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Icon(
                iconFor(row.kind),
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = row.title,
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            row.status?.let { status -> ToolStatusLabel(status) }
            Icon(
                if (expanded) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.ChevronRight,
                contentDescription = if (expanded) stringResource(R.string.common_collapse) else stringResource(R.string.common_expand),
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
        }
        if (expanded) {
            ToolCodeCard(row = row, onOpenDetail = onOpenDetail, onOpenReference = onOpenReference)
        }
    }
}

/** Status is an icon and a word, not a colour a reader has to decode. */
@Composable
private fun ToolStatusLabel(status: String) {
    val color = when (status) {
        "succeeded" -> MobileDesign.Good
        "failed" -> MaterialTheme.colorScheme.error
        "running" -> MobileDesign.Accent
        else -> MobileDesign.Muted
    }
    val label = when (status) {
        "succeeded" -> stringResource(R.string.common_success)
        "failed" -> stringResource(R.string.common_failure)
        "running" -> stringResource(R.string.common_working)
        else -> status
    }
    if (status == "running") {
        WorkingIndicator(size = 12.dp)
    } else {
        Icon(
            if (status == "failed") Icons.Rounded.Cancel else Icons.Rounded.CheckCircle,
            contentDescription = label,
            tint = color,
            modifier = Modifier.size(14.dp),
        )
    }
    Text(label, color = color, style = MaterialTheme.typography.labelMedium, maxLines = 1)
}

/** The pale card a tool row opens: full-width code first, a quiet full-record action last. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun ToolCodeCard(
    row: ToolRowModel,
    onOpenDetail: () -> Unit,
    onOpenReference: ((String) -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MobileDesign.Soft, RoundedCornerShape(MobileDesign.CardRadius))
            .border(0.5.dp, MobileDesign.Line, RoundedCornerShape(MobileDesign.CardRadius))
            .padding(CardInset),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        var hasBody = false
        if (!row.input.isNullOrBlank()) {
            ToolCodeBlock(row.input)
            hasBody = true
        }
        if (!row.output.isNullOrBlank()) {
            ToolCodeBlock(row.output)
            hasBody = true
        }
        if (!row.diff.isNullOrBlank()) {
            ToolCodeBlock(row.diff)
            hasBody = true
        }
        if (row.meta != null) {
            Text(
                text = row.meta,
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        row.completedAt?.let { at ->
            Text(
                text = stringResource(R.string.tool_card_completed_at, formatCompletedAt(at)),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        if (!hasBody) {
            Text(
                text = stringResource(R.string.common_no_content),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (onOpenReference != null && row.references.isNotEmpty()) {
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                row.references.forEach { path ->
                    Text(
                        text = stringResource(R.string.chat_open_reference, path.substringAfterLast('/').ifBlank { path }),
                        color = MobileDesign.Accent,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier
                            .background(MobileDesign.Canvas, RoundedCornerShape(50))
                            .clickable { onOpenReference(path) }
                            .padding(horizontal = 10.dp, vertical = 7.dp),
                    )
                }
            }
        }
        if (row.canOpenDetail) {
            Text(
                text = stringResource(R.string.chat_view_full_record),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .clickable(onClick = onOpenDetail)
                    .padding(horizontal = 4.dp, vertical = 2.dp),
            )
        }
    }
}

/** Tool text follows the page's own scroll, wraps long lines, and is selectable. */
@Composable
private fun ToolCodeBlock(text: String) {
    SelectionContainer(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = CodeBlockMaxHeight)
            .verticalScroll(rememberScrollState()),
    ) {
        Text(
            text = text,
            color = MobileDesign.Ink,
            fontFamily = FontFamily.Monospace,
            fontSize = 13.sp,
            lineHeight = 19.sp,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** The full record of one tool call, paged from the Bridge. */
@Composable
fun ToolDetailScreen(
    title: String,
    fields: List<String>,            // e.g. ["input", "output"] or ["diff"]
    selectedField: Int,
    text: String,
    /** More of the record follows this page. */
    hasMore: Boolean,
    /** An earlier page exists to step back to. */
    hasPrevious: Boolean,
    loading: Boolean,
    error: String?,
    onSelectField: (Int) -> Unit,
    onOlder: () -> Unit,
    onNewer: () -> Unit,
    onRefresh: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier.size(44.dp).clip(CircleShape).clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.ChevronLeft,
                    contentDescription = stringResource(R.string.common_back),
                    tint = MobileDesign.Ink,
                    modifier = Modifier.size(22.dp),
                )
            }
            Text(
                text = title,
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(horizontal = MobileDesign.PageInset)
                .padding(top = 4.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (fields.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    fields.forEachIndexed { index, field ->
                        val selected = index == selectedField
                        Text(
                            text = fieldLabel(field),
                            color = if (selected) MobileDesign.Canvas else MobileDesign.Ink,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier
                                .background(
                                    if (selected) MobileDesign.Ink else MobileDesign.Soft,
                                    RoundedCornerShape(50),
                                )
                                .clickable(enabled = !loading) { onSelectField(index) }
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                        )
                    }
                }
            }

            if (error != null) {
                Text(
                    text = error,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.labelMedium,
                )
            }

            val scrollState = rememberScrollState()
            LaunchedEffect(text) { scrollState.scrollTo(0) }
            Box(Modifier.fillMaxWidth().weight(1f)) {
                when {
                    loading && text.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) { WorkingIndicator() }
                    text.isEmpty() -> Text(
                        text = stringResource(R.string.common_no_content),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    else -> SelectionContainer(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(scrollState),
                    ) {
                        Text(
                            text = text,
                            color = MobileDesign.Ink,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                            lineHeight = 19.sp,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }

            if (hasMore) {
                Text(
                    text = stringResource(R.string.common_more_content),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (loading && text.isNotEmpty()) WorkingIndicator(size = 14.dp)
                PageAction(
                    stringResource(R.string.common_previous_page),
                    enabled = !loading && hasPrevious,
                    modifier = Modifier.weight(1f),
                    onClick = onNewer,
                )
                PageAction(stringResource(R.string.common_refresh), enabled = !loading, modifier = Modifier.weight(1f), onClick = onRefresh)
                PageAction(
                    stringResource(R.string.common_next_page),
                    enabled = !loading && hasMore,
                    modifier = Modifier.weight(1f),
                    onClick = onOlder,
                )
            }
        }
    }
}

@Composable
private fun PageAction(
    label: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .background(MobileDesign.Soft, RoundedCornerShape(50))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (enabled) MobileDesign.Ink else MobileDesign.Muted.copy(alpha = 0.45f),
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
private fun groupLabel(count: Int): String =
    if (count == 1) stringResource(R.string.chat_operation_count_singular)
    else stringResource(R.string.chat_operation_count_plural, count)

private fun iconFor(kind: String): ImageVector = when (kind) {
    "terminal" -> Icons.Rounded.Terminal
    "file_edit" -> Icons.Rounded.Description
    else -> Icons.Rounded.Build
}

@Composable
private fun fieldLabel(field: String): String = when (field) {
    "input" -> stringResource(R.string.common_input)
    "output" -> stringResource(R.string.common_output)
    "diff" -> stringResource(R.string.common_diff)
    else -> field
}

/** Today shows only the time; another day keeps the date, both in the system locale. */
private fun formatCompletedAt(at: java.time.Instant): String {
    val zone = java.time.ZoneId.systemDefault()
    val time = at.atZone(zone)
    val pattern = if (time.toLocalDate() == java.time.LocalDate.now(zone)) "HH:mm" else "MM-dd HH:mm"
    return time.format(java.time.format.DateTimeFormatter.ofPattern(pattern, java.util.Locale.getDefault()))
}
