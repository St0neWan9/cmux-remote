package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.data.FeedItem
import com.cmuxremote.mobile.data.FeedQuestion
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.markdown.MarkdownText
import com.cmuxremote.mobile.ui.theme.MobileDesign

/**
 * The decisions the Mac is waiting on, and the record of the ones already answered.
 * Every reply is one fixed choice: the phone never composes a command.
 */
@Composable
fun FeedScreen(
    items: List<FeedItem>,
    onBack: (() -> Unit)?,
    onAnswer: (String, List<String>) -> Unit,
    onDecide: (String, String, String) -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
    loading: Boolean = false,
    error: String? = null,
) {
    var history by remember { mutableStateOf(false) }
    val shown = items.filter { history || it.pending }
    val multipleHosts = items.map { it.hostID }.filter { it.isNotEmpty() }.distinct().size > 1
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas).testTag("feed.page")) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (onBack != null) {
                Box(Modifier.size(44.dp).clickable(onClick = onBack), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.ChevronLeft, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink)
                }
            }
            Text(stringResource(R.string.feed_title), color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            Text(
                text = if (history) stringResource(R.string.feed_all_events) else stringResource(R.string.feed_only_pending),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier
                    .testTag("feed.history.toggle")
                    .background(MobileDesign.Soft, CircleShape)
                    .clickable { history = !history }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
        if (loading && shown.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                androidx.compose.material3.CircularProgressIndicator(color = MobileDesign.Accent, strokeWidth = 2.dp)
            }
        } else if (shown.isEmpty()) {
            Text(
                text = if (history) stringResource(R.string.feed_no_events) else stringResource(R.string.feed_nothing_to_answer),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(shown, key = { it.hostID + ":" + it.requestID }) { item ->
                // A record is never actionable, even if it is a question or permission kind.
                if (!item.pending) {
                    RecordCard(item, showHost = multipleHosts)
                } else {
                    when (item.kind) {
                        "question" -> QuestionFormCard(
                            questions = item.questions.map { question ->
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
                            busy = busy,
                            answered = item.selections.takeIf { it.isNotEmpty() },
                            tag = "feed.question." + item.requestID,
                            onSubmit = { labels -> onAnswer(item.requestID, labels) },
                        )
                        "permissionRequest" -> PermissionDecisionCard(
                            title = item.title.ifBlank { item.toolName ?: stringResource(R.string.feed_needs_permission) },
                            subject = item.toolInput,
                            busy = busy,
                            allowedModes = com.cmuxremote.mobile.data.FeedDecisionPolicy.permissionModes(item),
                            onDecide = { mode -> onDecide(item.requestID, item.kind, mode) },
                        )
                        "exitPlan" -> PlanDecisionCard(
                            title = item.title.ifBlank { stringResource(R.string.feed_plan_confirmation) },
                            plan = item.plan,
                            busy = busy,
                            allowedModes = com.cmuxremote.mobile.data.FeedDecisionPolicy.planModes(item),
                            onDecide = { mode, feedback -> onDecide(item.requestID, item.kind, mode + "\u0000" + (feedback ?: "")) },
                        )
                        else -> {
                            RecordCard(item, showHost = multipleHosts)
                            // A pending event of an unknown kind still needs an explanation.
                            Text(
                                stringResource(R.string.feed_unsupported),
                                color = MobileDesign.Muted,
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
            }
            if (error != null) {
                item {
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}

/** A Feed event that needs no reply, or one already decided. */
@Composable
private fun RecordCard(item: FeedItem, showHost: Boolean) {
    FloatingSurface(contentPadding = PaddingValues(16.dp)) {
        Text(
            text = item.title.ifBlank { item.toolName ?: stringResource(R.string.feed_event) },
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.bodyLarge,
        )
        if (showHost && item.hostName.isNotBlank()) {
            Text(item.hostName, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        // The prompt's own words, above its choices.
        if (!item.questionPrompt.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(item.questionPrompt, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
        }
        if (!item.body.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(item.body, color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
        }
        if (!item.plan.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            MarkdownText(item.plan)
        }
        if (!item.text.isNullOrBlank() || !item.reason.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            MarkdownText(item.text ?: item.reason.orEmpty())
        }
        if (!item.toolInput.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(
                item.toolInput,
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
            )
        }
        if (item.toolResult != null) {
            Spacer(Modifier.height(6.dp))
            if (item.toolResultIsError) {
                Text(stringResource(R.string.chat_tool_failed), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
            }
            Text(
                item.toolResult,
                color = if (item.toolResultIsError) MaterialTheme.colorScheme.error else MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
            )
        }
        if (item.toolResultTruncated || item.toolInputTruncated || item.planTruncated) {
            Text(stringResource(R.string.project_truncated), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        item.todos.forEach { todo ->
            Spacer(Modifier.height(2.dp))
            Text(
                text = (if (todo.completed) "✓ " else "○ ") + todo.content,
                color = if (todo.completed) MobileDesign.Muted else MobileDesign.Ink,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = when (item.status) {
                "pending" -> stringResource(R.string.feed_status_pending)
                "expired" -> stringResource(R.string.feed_status_expired)
                "resolved" -> stringResource(R.string.feed_status_resolved)
                else -> stringResource(R.string.feed_status_recorded)
            } + (item.decisionMode?.let { " · " + decisionModeLabel(it) } ?: ""),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.labelMedium,
        )
        if (item.feedback != null) {
            Text(item.feedback, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        item.selections.forEach { Text(it, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium) }
    }
}

/** Localized record label; the raw enum value must not leak into the page. */
@Composable
private fun decisionModeLabel(mode: String): String = when (mode) {
    "once" -> stringResource(R.string.feed_allow_once)
    "always" -> stringResource(R.string.feed_mode_always_label)
    "all" -> stringResource(R.string.feed_mode_all_label)
    "bypass" -> stringResource(R.string.feed_mode_bypass_label)
    "deny" -> stringResource(R.string.feed_deny)
    "manual" -> stringResource(R.string.feed_continue_after_edit)
    "ultraplan" -> stringResource(R.string.feed_deep_plan)
    "bypassPermissions" -> stringResource(R.string.feed_execute_plan)
    "autoAccept" -> stringResource(R.string.feed_auto_accept)
    else -> mode
}
