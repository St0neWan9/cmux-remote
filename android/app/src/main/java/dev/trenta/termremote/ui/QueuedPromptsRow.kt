package dev.trenta.termremote.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Queue
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.trenta.termremote.R
import dev.trenta.termremote.data.QueuedPromptInfo
import dev.trenta.termremote.ui.theme.MobileDesign

/**
 * Prompts waiting in the agent's input queue while a turn runs, above the composer.
 *
 * Mirrors `BackgroundTasksRow` in layout and tone so every connected device sees the
 * same queue without leaving stuck "waiting for agent" bubbles in the timeline.
 */
@Composable
fun QueuedPromptsRow(
    prompts: List<QueuedPromptInfo>,
    modifier: Modifier = Modifier,
) {
    if (prompts.isEmpty()) return
    var expanded by remember { mutableStateOf(true) }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .animateContentSize(animationSpec = androidx.compose.animation.core.tween(180, easing = androidx.compose.animation.core.FastOutSlowInEasing))
            .padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("chat.queued")
                .clip(RoundedCornerShape(12.dp))
                .clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Queue,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = if (prompts.size == 1) {
                    stringResource(R.string.chat_queued_one)
                } else {
                    stringResource(R.string.chat_queued_count, prompts.size)
                },
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(14.dp),
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 2.dp).testTag("chat.queued.list"),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                prompts.forEachIndexed { index, prompt ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("chat.queued.item"),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        Text(
                            text = "${index + 1}.",
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace),
                            modifier = Modifier.alignByBaseline(),
                        )
                        Text(
                            text = prompt.text,
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f).alignByBaseline(),
                        )
                    }
                }
            }
        }
    }
}
