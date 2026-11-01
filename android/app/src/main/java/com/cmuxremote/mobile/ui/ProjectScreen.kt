package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.adaptive.PaneLayoutPolicy
import com.cmuxremote.mobile.data.ProjectChange
import com.cmuxremote.mobile.data.ProjectText
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign

private const val LIST_WIDTH_DP = 240

/** A conversation's uncommitted project: changed paths beside the selected file's text. */
@Composable
fun ProjectScreen(
    title: String,
    changes: List<ProjectChange>,
    selectedPath: String?,
    text: ProjectText?,
    loading: Boolean,
    error: String?,
    onBack: () -> Unit,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    onOpenPath: ((String) -> Unit)? = null,
    onRefresh: (() -> Unit)? = null,
    /** `changes`, `diff` or `file`; the page keeps the reader's choice on refresh. */
    mode: String = "changes",
    inputPath: String = "",
    onPathChange: (String) -> Unit = {},
    onOpenPathInput: () -> Unit = {},
    onShowChanges: () -> Unit = {},
    onShowDiff: () -> Unit = {},
) {
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    val context = androidx.compose.ui.platform.LocalContext.current
    Column(
        modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        ProjectHeader(
            title = title,
            onBack = onBack,
            onCopy = text?.let { shown ->
                {
                    clipboard.setText(androidx.compose.ui.text.AnnotatedString(shown.text))
                }
            },
            onShare = text?.let { shown ->
                {
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(android.content.Intent.EXTRA_TEXT, shown.text)
                    }
                    context.startActivity(
                        android.content.Intent.createChooser(send, null)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            },
            onRefresh = onRefresh,
        )
        if (error != null) {
            Text(
                error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 4.dp),
            )
        }
        // A relative path can be read directly; the three resources mirror the
        // iPhone page and never pretend a whole-tree diff is one file.
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = inputPath,
                onValueChange = onPathChange,
                modifier = Modifier.weight(1f).testTag("project.path"),
                singleLine = true,
                textStyle = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace),
                placeholder = { Text(stringResource(R.string.project_path_placeholder), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium) },
                shape = RoundedCornerShape(14.dp),
            )
            Text(
                text = stringResource(R.string.project_read_file),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.clip(CircleShape).clickable(onClick = onOpenPathInput).padding(horizontal = 8.dp, vertical = 8.dp),
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ModeChoice(stringResource(R.string.project_read_file_short), mode == "file", "project.mode.file", onOpenPathInput)
            ModeChoice(stringResource(R.string.project_diff), mode == "diff", "project.mode.diff", onShowDiff)
            ModeChoice(stringResource(R.string.project_changed_files), mode == "changes", "project.mode.changes", onShowChanges)
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            // Mirrors PaneLayoutPolicy: a phone in landscape stays on the shorter side.
            val compact = minOf(maxWidth, maxHeight).value < PaneLayoutPolicy.COMPACT_MAX_DP
            if (loading && changes.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    WorkingIndicator()
                }
            } else if (compact) {
                CompactProjectBody(
                    changes = changes,
                    selectedPath = selectedPath,
                    text = text,
                    loading = loading,
                    mode = mode,
                    onSelect = onSelect,
                )
            } else {
                WideProjectBody(
                    changes = changes,
                    selectedPath = selectedPath,
                    text = text,
                    loading = loading,
                    mode = mode,
                    onSelect = onSelect,
                )
            }
        }
    }
}

@Composable
private fun ProjectHeader(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    onCopy: (() -> Unit)? = null,
    onShare: (() -> Unit)? = null,
    onRefresh: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier.size(44.dp).clip(CircleShape).clickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.ChevronLeft, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink, modifier = Modifier.size(22.dp))
        }
        Text(
            title,
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (onCopy != null) HeaderAction(stringResource(R.string.common_copy), onCopy)
        if (onShare != null) HeaderAction(stringResource(R.string.common_share), onShare)
        if (onRefresh != null) HeaderAction(stringResource(R.string.common_refresh), onRefresh)
    }
}

@Composable
private fun ModeChoice(label: String, selected: Boolean, tag: String, onClick: () -> Unit) {
    Text(
        text = label,
        color = if (selected) MobileDesign.Canvas else MobileDesign.Muted,
        style = MaterialTheme.typography.labelMedium,
        maxLines = 1,
        modifier = Modifier
            .testTag(tag)
            .clip(CircleShape)
            .background(if (selected) MobileDesign.Ink else MobileDesign.Soft)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

@Composable
private fun HeaderAction(label: String, onClick: () -> Unit) {
    Text(
        text = label,
        color = MobileDesign.Accent,
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
    )
}

/** Phone portrait: changed paths above the text, in one scrollable column. */
@Composable
private fun CompactProjectBody(
    changes: List<ProjectChange>,
    selectedPath: String?,
    text: ProjectText?,
    loading: Boolean,
    mode: String,
    onSelect: (String) -> Unit,
) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        if (mode == "changes") {
            if (changes.isEmpty()) {
                if (!loading) {
                    Text(
                        stringResource(R.string.project_empty),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
                    )
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                    changes.forEach { change ->
                        ChangeRow(
                            change = change,
                            selected = change.path == selectedPath,
                            onClick = { onSelect(change.path) },
                        )
                    }
                }
            }
        }
        when {
            loading -> Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                WorkingIndicator()
            }
            text != null && text.text.isEmpty() -> Text(
                stringResource(R.string.project_no_content),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
            )
            text != null -> ProjectTextBlock(
                text = text,
                modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
            )
        }
    }
}

/** Foldable and tablet: the path list at a fixed width, the text filling the rest. */
@Composable
private fun WideProjectBody(
    changes: List<ProjectChange>,
    selectedPath: String?,
    text: ProjectText?,
    loading: Boolean,
    mode: String,
    onSelect: (String) -> Unit,
) {
    Row(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.width(LIST_WIDTH_DP.dp).fillMaxHeight(),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            if (changes.isEmpty()) {
                if (!loading) {
                    item {
                        Text(
                            stringResource(R.string.project_empty),
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(horizontal = MobileDesign.PageInset, vertical = 8.dp),
                        )
                    }
                }
            } else {
                items(changes) { change ->
                    ChangeRow(
                        change = change,
                        selected = change.path == selectedPath,
                        onClick = { onSelect(change.path) },
                    )
                }
            }
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(MobileDesign.Line))
        Box(Modifier.weight(1f).fillMaxHeight()) {
            when {
                loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    WorkingIndicator()
                }
                text != null && text.text.isEmpty() -> Text(
                    stringResource(R.string.project_no_content),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
                )
                text != null -> Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
                ) {
            ProjectTextBlock(text)
                }
            }
        }
    }
}

@Composable
private fun ChangeRow(change: ProjectChange, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .testTag("project.change." + change.path)
            .heightIn(min = MobileDesign.Control)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) MobileDesign.AccentSoft else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = change.status,
            color = if (selected) MobileDesign.Accent else MobileDesign.Muted,
            fontFamily = FontFamily.Monospace,
            fontSize = 11.sp,
            lineHeight = 13.sp,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier
                .clip(RoundedCornerShape(5.dp))
                .background(MobileDesign.Code)
                .padding(horizontal = 5.dp, vertical = 3.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = change.path,
                color = if (selected) MobileDesign.Accent else MobileDesign.Ink,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            // A rename or copy keeps the path it came from.
            change.oldPath?.let { old ->
                Text(
                    text = old + " → " + change.path,
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Icon(
            Icons.Rounded.ChevronRight,
            contentDescription = null,
            tint = MobileDesign.Muted,
            modifier = Modifier.size(16.dp),
        )
    }
}

/** The diff or file body, always monospace and scrollable sideways for long lines. */
@Composable
private fun ProjectTextBlock(text: ProjectText, modifier: Modifier = Modifier) {
    val horizontal = rememberScrollState()
    LaunchedEffect(text.path) { horizontal.scrollTo(0) }
    Column(modifier) {
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MobileDesign.Code)) {
            Box(Modifier.horizontalScroll(horizontal).padding(12.dp)) {
                SelectionContainer {
                    Text(
                        text = text.text,
                        color = MobileDesign.Ink,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        lineHeight = 17.sp,
                        maxLines = Int.MAX_VALUE,
                        softWrap = false,
                    )
                }
            }
        }
        if (text.truncated) {
            Text(
                stringResource(R.string.project_truncated),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}
