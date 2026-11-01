package com.cmuxremote.mobile.ui

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.BuildConfig
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.data.Diagnostics
import com.cmuxremote.mobile.ui.theme.MobileDesign
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay

private const val COPIED_HOLD_MILLIS = 2_000L

private val TimeFormat = DateTimeFormatter.ofPattern("HH:mm:ss.SSS", java.util.Locale.getDefault())

private val DebugColor = MobileDesign.Muted
private val InfoColor = Color(0xFF2F6BFF)
private val WarningColor = Color(0xFFC77700)
private val ErrorColor = Color(0xFFD70015)

/** The on-device log, newest first, with the build a report came from above it. */
@Composable
fun DiagnosticLogScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    var entries by remember { mutableStateOf(Diagnostics.entries()) }
    var copied by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current

    fun refresh() {
        entries = Diagnostics.entries()
    }

    LaunchedEffect(Unit) { refresh() }
    LaunchedEffect(copied) {
        if (copied) {
            delay(COPIED_HOLD_MILLIS)
            copied = false
        }
    }

    Column(
        modifier
            .fillMaxSize()
            .testTag("diagnostics.page")
            .background(MobileDesign.Canvas)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier.size(44.dp).clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.ChevronLeft, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink)
            }
            Text(
                stringResource(R.string.diagnostics_title),
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        SelectionContainer {
            Text(
                text = buildLabel(),
                color = MobileDesign.Muted,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                lineHeight = 15.sp,
                modifier = Modifier.fillMaxWidth()
                    .padding(horizontal = MobileDesign.PageInset, vertical = 4.dp),
            )
        }
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(entries) { entry -> EntryRow(entry) }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(MobileDesign.PageInset),
            horizontalArrangement = Arrangement.spacedBy(MobileDesign.RowGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(
                onClick = {
                    clipboard.setText(AnnotatedString(Diagnostics.report()))
                    copied = true
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
                contentPadding = PaddingValues(horizontal = 8.dp),
                modifier = Modifier.weight(1f).height(MobileDesign.Control),
            ) {
                Text(
                    text = if (copied) stringResource(R.string.common_copied) else stringResource(R.string.diagnostics_copy_report),
                    color = MobileDesign.Canvas,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            OutlinedButton(
                onClick = {
                    Diagnostics.clear()
                    refresh()
                },
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 8.dp),
                modifier = Modifier.weight(1f).height(MobileDesign.Control),
            ) {
                Text(
                    text = stringResource(R.string.diagnostics_clear),
                    color = ErrorColor,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            OutlinedButton(
                onClick = { refresh() },
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 8.dp),
                modifier = Modifier.weight(1f).height(MobileDesign.Control),
            ) {
                Text(
                    text = stringResource(R.string.common_refresh),
                    color = MobileDesign.Ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun EntryRow(entry: Diagnostics.Entry) {
    val level = entry.level.name.uppercase(java.util.Locale.getDefault())
    // Two lines as on the iPhone: level/time/category, then the message itself.
    val header = buildAnnotatedString {
        withStyle(SpanStyle(color = MobileDesign.Muted)) { append("${clock(entry.atMillis)}  ") }
        withStyle(SpanStyle(color = levelColor(entry.level), fontWeight = FontWeight.SemiBold)) {
            append("$level  ")
        }
        withStyle(SpanStyle(color = MobileDesign.Muted)) { append(entry.category) }
    }
    SelectionContainer {
        Column {
            Text(
                text = header,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                lineHeight = 16.sp,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = entry.message,
                color = MobileDesign.Ink,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                lineHeight = 16.sp,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

private fun buildLabel(): String {
    val version = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
    return "cmux-remote $version · Android ${Build.VERSION.RELEASE ?: "?"}"
}

private fun clock(atMillis: Long): String =
    Instant.ofEpochMilli(atMillis).atZone(ZoneId.systemDefault()).format(TimeFormat)

private fun levelColor(level: Diagnostics.Level): Color = when (level) {
    Diagnostics.Level.Debug -> DebugColor
    Diagnostics.Level.Info -> InfoColor
    Diagnostics.Level.Warning -> WarningColor
    Diagnostics.Level.Error -> ErrorColor
}
