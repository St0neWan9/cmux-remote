package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** One approved workspace that can start a conversation. */
data class StartWorkspace(val id: String, val title: String)

/** A folder offered as the working directory for a new conversation. */
data class StartRoot(val id: String, val path: String)

private const val PromptLimitBytes = 4096

/**
 * Starts a new conversation: workspace, working directory, agent and optional first message.
 * A sheet-like page, so it stays one column at every width.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StartSessionScreen(
    workspaces: List<StartWorkspace>,
    selectedWorkspace: StartWorkspace?,
    roots: List<StartRoot>,
    selectedRoot: StartRoot?,
    agents: List<String>,          // e.g. ["claude", "codex"]
    selectedAgent: String,
    prompt: String,
    busy: Boolean,
    error: String?,
    notice: String?,
    onBack: () -> Unit,
    onPickWorkspace: (StartWorkspace) -> Unit,
    onPickRoot: (StartRoot) -> Unit,
    onPickAgent: (String) -> Unit,
    onPrompt: (String) -> Unit,
    onStart: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val canStart = selectedWorkspace != null &&
        selectedRoot != null &&
        !busy &&
        !(selectedAgent == "codex" && prompt.isBlank())

    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onBack),
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
                text = stringResource(R.string.start_title),
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(MobileDesign.PageInset),
            verticalArrangement = Arrangement.spacedBy(MobileDesign.SectionGap),
        ) {
            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                SectionLabel(stringResource(R.string.start_workspace))
                Spacer(Modifier.height(10.dp))
                if (workspaces.isEmpty()) {
                    Text(stringResource(R.string.start_no_workspaces), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                } else {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        workspaces.forEach { workspace ->
                            ChoiceChip(
                                text = workspace.title,
                                selected = workspace.id == selectedWorkspace?.id,
                                onClick = { onPickWorkspace(workspace) },
                            )
                        }
                    }
                }
            }

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                SectionLabel(stringResource(R.string.start_directory))
                Spacer(Modifier.height(10.dp))
                if (roots.isEmpty()) {
                    Text(stringResource(R.string.start_no_directories), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        roots.forEach { root ->
                            RootRow(
                                root = root,
                                selected = root.id == selectedRoot?.id,
                                onClick = { onPickRoot(root) },
                            )
                        }
                    }
                }
            }

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                SectionLabel(stringResource(R.string.start_agent))
                Spacer(Modifier.height(10.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    agents.forEach { agent ->
                        ChoiceChip(
                            text = agent.replaceFirstChar { it.uppercase() },
                            selected = agent == selectedAgent,
                            onClick = { onPickAgent(agent) },
                        )
                    }
                }
            }

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel(stringResource(R.string.start_first_message), modifier = Modifier.weight(1f))
                    Text(
                        text = stringResource(R.string.start_byte_count, utf8Size(prompt), PromptLimitBytes),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = prompt,
                    onValueChange = { next ->
                        // Stop accepting input once the message would pass 4 KiB of UTF-8.
                        if (utf8Size(next) <= PromptLimitBytes) onPrompt(next)
                    },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.start_prompt_placeholder), color = MobileDesign.Muted) },
                    minLines = 3,
                    maxLines = 6,
                    singleLine = false,
                )
                if (selectedAgent == "codex") {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = stringResource(R.string.start_codex_required),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }

            if (error != null) {
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
            if (notice != null) {
                Text(notice, color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            }

            Button(
                onClick = onStart,
                enabled = canStart,
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth().heightIn(min = MobileDesign.Control),
                colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
            ) {
                Text(
                    text = if (busy) stringResource(R.string.start_starting) else stringResource(R.string.start_start),
                    color = if (canStart) MobileDesign.Canvas else MobileDesign.Muted,
                )
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, style = MaterialTheme.typography.labelMedium, color = MobileDesign.Muted)
}

@Composable
private fun ChoiceChip(text: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text = text,
        color = if (selected) MobileDesign.Canvas else MobileDesign.Ink,
        style = MaterialTheme.typography.labelMedium,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (selected) MobileDesign.Ink else MobileDesign.Soft)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

@Composable
private fun RootRow(root: StartRoot, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) MobileDesign.AccentSoft else MobileDesign.Soft)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Rounded.Folder,
            contentDescription = null,
            tint = if (selected) MobileDesign.Accent else MobileDesign.Muted,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = root.path,
            color = if (selected) MobileDesign.Accent else MobileDesign.Ink,
            style = MaterialTheme.typography.labelMedium,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Icon(
                Icons.Rounded.Check,
                contentDescription = stringResource(R.string.start_selected),
                tint = MobileDesign.Accent,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

private fun utf8Size(text: String): Int = text.toByteArray(Charsets.UTF_8).size
