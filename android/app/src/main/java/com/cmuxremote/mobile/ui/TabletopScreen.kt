package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.ConversationUi
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.adaptive.PaneLayout
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.theme.MobileDesign

/**
 * Half-open posture: the transcript stays in the top half, and the decision or
 * draft you act on sits in the bottom half, clear of the fold.
 */
@Composable
fun TabletopScreen(
    state: ConversationUi,
    layout: PaneLayout.Tabletop,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    onAnswer: (String, List<String>) -> Unit,
    onDecide: (String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        ConversationHeader(title = state.session.title, subtitle = state.session.agent.replaceFirstChar { it.uppercase() })
        ConversationTimeline(state = state, modifier = Modifier.weight(layout.topHeightDp))
        Box(Modifier.fillMaxWidth().height(layout.gapDp.dp).background(MobileDesign.Line))
        Column(
            modifier = Modifier.weight(layout.bottomHeightDp).fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val pending = state.feed.firstOrNull { it.status == "pending" }
            if (pending != null) {
                PendingDecisionCard(
                    title = pending.title.ifBlank { stringResource(R.string.feed_needs_confirmation) },
                    question = pending.questions.firstOrNull(),
                    onAnswer = { labels -> onAnswer(pending.requestID, labels) },
                    onMode = { mode -> onDecide(pending.requestID, mode) },
                )
            }
            Spacer(Modifier.weight(1f))
            ComposerArea(
                draft = state.draft,
                onDraftChange = onDraft,
                onSend = onSend,
                onStop = onStop,
                working = state.session.working,
                canSend = state.session.writable,
                sending = state.sending,
                hasBackgroundTasks = false,
                error = state.error,
            )
        }
    }
}

/** One pending Feed decision in the bottom half. */
@Composable
fun PendingDecisionCard(
    title: String,
    question: com.cmuxremote.mobile.data.FeedQuestion?,
    onAnswer: (List<String>) -> Unit,
    onMode: (String) -> Unit,
) {
    FloatingSurface(contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)) {
        Text(stringResource(R.string.feed_needs_confirmation), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        Spacer(Modifier.height(6.dp))
        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        if (question != null) {
            Spacer(Modifier.height(8.dp))
            Text(question.prompt, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                question.options.take(2).forEachIndexed { index, option ->
                    if (index == 0) {
                        Button(
                            onClick = { onAnswer(listOf(option)) },
                            colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
                            shape = RoundedCornerShape(50),
                            modifier = Modifier.weight(1f),
                        ) { Text(option, color = MobileDesign.Canvas, maxLines = 1) }
                    } else {
                        OutlinedButton(
                            onClick = { onAnswer(listOf(option)) },
                            shape = RoundedCornerShape(50),
                            modifier = Modifier.weight(1f),
                        ) { Text(option, color = MobileDesign.Ink, maxLines = 1) }
                    }
                }
            }
        } else {
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { onMode("once") },
                    colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
                    shape = RoundedCornerShape(50),
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.feed_allow_once), color = MobileDesign.Canvas) }
                OutlinedButton(
                    onClick = { onMode("deny") },
                    shape = RoundedCornerShape(50),
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.feed_deny), color = MobileDesign.Ink) }
            }
        }
    }
}

/** Third column on very wide windows: the project and diff surface. */
@Composable
fun SupportingPane(messages: List<com.cmuxremote.mobile.data.ChatMessage>, modifier: Modifier = Modifier) {
    val edited = messages.lastOrNull { it.kind == "file_edit" }
    Column(
        modifier = modifier.fillMaxHeight().background(MobileDesign.Soft).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.feed_changes), color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium)
        if (edited == null) {
            Text(stringResource(R.string.feed_no_changes), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        } else {
            FloatingSurface(contentPadding = androidx.compose.foundation.layout.PaddingValues(14.dp)) {
                Text(edited.filePath ?: stringResource(R.string.common_file), color = MobileDesign.Ink, style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.height(8.dp))
                Text(
                    edited.diff ?: stringResource(R.string.feed_no_diff),
                    color = MobileDesign.Muted,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                )
            }
        }
    }
}
