package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.TerminalUi
import com.cmuxremote.mobile.ui.theme.MobileDesign

/// A provider-neutral terminal without a proved Agent: a bounded text screen
/// with explicit input. It never pretends to be a conversation.
@Composable
fun TerminalScreen(
    state: TerminalUi,
    onBack: () -> Unit,
    onSend: (String, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by rememberSaveable { mutableStateOf("") }
    val scroll = rememberScrollState()
    LaunchedEffect(state.text) { scroll.animateScrollTo(scroll.maxValue) }
    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = androidx.compose.ui.res.stringResource(R.string.common_back))
            }
            Text(
                state.session.title,
                style = MaterialTheme.typography.titleMedium,
                color = MobileDesign.Ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (state.busy) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
        }
        HorizontalDivider(color = MobileDesign.Line, thickness = 0.5.dp)
        Column(
            modifier = Modifier.weight(1f).verticalScroll(scroll).padding(12.dp),
        ) {
            Text(
                state.text.ifEmpty { " " },
                fontFamily = FontFamily.Monospace,
                fontSize = 12.sp,
                color = MobileDesign.Ink,
            )
        }
        state.error?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text("Command") },
                maxLines = 3,
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = { onSend(draft, true); draft = "" },
                enabled = draft.isNotBlank() && !state.busy,
            ) { Text(androidx.compose.ui.res.stringResource(R.string.chat_send)) }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(onClick = { onSend("\u001b", false) }, enabled = !state.busy) { Text("Esc") }
            OutlinedButton(onClick = { onSend("\u0003", false) }, enabled = !state.busy) { Text("Ctrl-C") }
            OutlinedButton(onClick = { onSend("\t", false) }, enabled = !state.busy) { Text("Tab") }
        }
    }
}
