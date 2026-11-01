package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

private const val COPIED_HOLD_MILLIS = 2_000L

// The platform's localized short styles, so a date reads the way the reader's
// locale writes it instead of a fixed 24-hour pattern.
private val SameDayTime = DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT)
private val OtherDayTime = DateTimeFormatter.ofLocalizedDateTime(
    java.time.format.FormatStyle.SHORT,
    java.time.format.FormatStyle.SHORT,
)

/** A message's text on its own page, where any part of it can be selected and copied. */
@Composable
fun SelectTextScreen(
    title: String,
    text: String,
    monospaced: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(COPIED_HOLD_MILLIS)
            copied = false
        }
    }

    Column(
        modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        PageHeader(title, onBack) {
            TextButton(
                onClick = {
                    clipboard.setText(AnnotatedString(text))
                    copied = true
                },
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text(
                    text = if (copied) stringResource(R.string.common_copied) else stringResource(R.string.common_copy),
                    color = MobileDesign.Accent,
                    fontSize = 13.sp,
                    maxLines = 1,
                )
            }
        }
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            SelectionContainer {
                Text(
                    text = text,
                    color = MobileDesign.Ink,
                    fontFamily = if (monospaced) FontFamily.Monospace else FontFamily.Default,
                    fontSize = if (monospaced) 12.sp else MaterialTheme.typography.bodyLarge.fontSize,
                    lineHeight = if (monospaced) 18.sp else MaterialTheme.typography.bodyLarge.lineHeight,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

/** "运行中 3m 47s" or "正在压缩上下文…", updating once per second. */
@Composable
fun LiveRunLabel(since: Instant, compacting: Boolean, modifier: Modifier = Modifier) {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(since) {
        while (true) {
            now = Instant.now()
            delay(1_000)
        }
    }
    val seconds = Duration.between(since, now).seconds.coerceAtLeast(0L).toInt()
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(
            text = if (compacting) stringResource(R.string.chat_compacting)
            else stringResource(R.string.chat_running_timer, runTimer(seconds)),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
        )
    }
}

/** "用时 3m 47s" divider shown above a finished reply. */
@Composable
fun ResponseRunLabel(seconds: Double, recorded: Boolean, modifier: Modifier = Modifier) {
    val duration = compactDuration(seconds)
    Column(
        modifier = modifier.fillMaxWidth().padding(top = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = if (recorded) stringResource(R.string.chat_used_time, duration)
            else stringResource(R.string.chat_used_time_approx, duration),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
        )
        Spacer(Modifier.size(10.dp))
        HorizontalDivider(color = Color.Black.copy(alpha = 0.1f), thickness = 0.5.dp)
    }
}

/** Footer under a finished reply: copy, share, quote, select text, completion time. */
@Composable
fun ResponseFooter(
    completedAt: Instant?,
    onCopy: () -> Unit,
    onShare: () -> Unit,
    onQuote: () -> Unit,
    onSelectText: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var copied by remember { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(copied) {
        if (copied) {
            kotlinx.coroutines.delay(2_000)
            copied = false
        }
    }
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FooterAction(if (copied) stringResource(R.string.common_copied) else stringResource(R.string.common_copy)) {
            onCopy()
            copied = true
        }
        FooterAction(stringResource(R.string.common_share), onShare)
        FooterAction(stringResource(R.string.common_quote), onQuote)
        FooterAction(stringResource(R.string.common_select_text), onSelectText)
        Spacer(Modifier.weight(1f))
        if (completedAt != null) {
            Text(
                text = completionTime(completedAt),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                modifier = Modifier.padding(start = 10.dp),
            )
        }
    }
}

/** Recorded conversation time and the number of completed turns that contributed it. */
@Composable
fun TimingScreen(
    recordedSeconds: Double?,
    turns: Int,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        PageHeader(stringResource(R.string.chat_timing_title), onBack)
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(MobileDesign.PageInset),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            if (recordedSeconds != null) {
                ResponseRunLabel(seconds = recordedSeconds, recorded = true)
                Text(
                    text = stringResource(R.string.chat_recorded_turns, turns),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                Text(
                    text = stringResource(R.string.chat_no_timing),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Text(
                text = stringResource(R.string.chat_timing_note),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun PageHeader(
    title: String,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
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
        trailing?.invoke()
    }
}

@Composable
private fun FooterAction(label: String, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
    ) {
        Text(text = label, color = MobileDesign.Muted, fontSize = 13.sp, maxLines = 1)
    }
}

/** `47s` or `3m 47s`, the same spelling as the finished label. */
private fun runTimer(seconds: Int): String {
    val total = seconds.coerceAtLeast(0)
    if (total < 60) return "${total}s"
    return String.format(java.util.Locale.getDefault(), "%dm %02ds", total / 60, total % 60)
}

/** `3m 47s`, with units the reader's language spells itself. */
@Composable
private fun compactDuration(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).roundToInt()
    return when {
        total < 60 -> stringResource(R.string.chat_duration_seconds, total)
        total < 3_600 -> stringResource(R.string.chat_duration_minutes, total / 60, total % 60)
        else -> stringResource(R.string.chat_duration_hours, total / 3_600, (total % 3_600) / 60)
    }
}

/** Today's completion time is `HH:mm`; another day's adds `MM-dd`. */
private fun completionTime(instant: Instant): String {
    val zone = ZoneId.systemDefault()
    val local = instant.atZone(zone)
    val formatter = if (local.toLocalDate() == LocalDate.now(zone)) SameDayTime else OtherDayTime
    return formatter.format(local)
}
