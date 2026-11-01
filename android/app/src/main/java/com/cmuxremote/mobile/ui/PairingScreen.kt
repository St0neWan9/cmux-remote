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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Laptop
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ShellState
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** First use: the Mac shows an expiring code, this device asks to be enrolled. */
@Composable
fun PairingScreen(
    state: ShellState.Pairing,
    onPair: (String) -> Unit,
    onRetrySaved: () -> Unit,
    onScan: (() -> Unit)? = null,
    discovered: List<com.cmuxremote.mobile.bridge.DiscoveredBridge> = emptyList(),
    approvedHostIDs: Set<String> = emptySet(),
    onPairDiscovered: ((com.cmuxremote.mobile.bridge.DiscoveredBridge) -> Unit)? = null,
    onBack: (() -> Unit)? = null,
) {
    var code by remember { mutableStateOf("") }
    var trusting by remember { mutableStateOf<com.cmuxremote.mobile.bridge.DiscoveredBridge?>(null) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .verticalScroll(rememberScrollState())
            .padding(MobileDesign.PageInset),
        verticalArrangement = Arrangement.spacedBy(MobileDesign.SectionGap),
    ) {
        Spacer(Modifier.height(8.dp))
        if (onBack != null) {
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
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Rounded.Laptop, null, tint = MobileDesign.Muted, modifier = Modifier.size(22.dp))
            Text(stringResource(R.string.pair_title), style = MaterialTheme.typography.titleLarge, color = MobileDesign.Ink)
        }
        Text(
            stringResource(R.string.pair_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MobileDesign.Muted,
        )
        FloatingSurface(contentPadding = PaddingValues(16.dp)) {
            Text(stringResource(R.string.pair_code_label), style = MaterialTheme.typography.labelMedium, color = MobileDesign.Muted)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = code,
                onValueChange = { code = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("cmux-remote://enroll?v=2&payload=…", color = MobileDesign.Muted) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                singleLine = false,
                maxLines = 4,
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { onPair(code) },
                enabled = code.isNotBlank() && !state.busy,
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
            ) {
                Icon(Icons.Rounded.QrCodeScanner, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(
                    if (state.busy) stringResource(R.string.pair_requesting) else stringResource(R.string.pair_request_access),
                    color = MobileDesign.Canvas,
                )
            }
            if (state.error != null) {
                Spacer(Modifier.height(10.dp))
                Text(state.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
            if (state.notice != null) {
                Spacer(Modifier.height(10.dp))
                Text(state.notice, color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (onScan != null) {
            TextButton(onClick = onScan) {
                Icon(Icons.Rounded.QrCodeScanner, null, tint = MobileDesign.Accent, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(6.dp))
                Text(stringResource(R.string.pair_scan), color = MobileDesign.Accent)
            }
        }
        if (onPairDiscovered != null) {
            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                Text(stringResource(R.string.pair_nearby), color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                if (discovered.isEmpty()) {
                    Text(stringResource(R.string.pair_searching), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                }
                discovered.forEach { bridge ->
                    val approved = bridge.host.id in approvedHostIDs
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !approved) { trusting = bridge }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            if (approved) Icons.Rounded.CheckCircle else Icons.Rounded.Laptop,
                            contentDescription = null,
                            tint = if (approved) MobileDesign.Good else MobileDesign.Muted,
                            modifier = Modifier.size(18.dp),
                        )
                        Column(Modifier.weight(1f)) {
                            Text(bridge.host.name, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                bridge.host.id.take(12).uppercase(),
                                color = MobileDesign.Muted,
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
            }
        }
        TextButton(onClick = onRetrySaved) {
            Text(stringResource(R.string.pair_retry_saved), color = MobileDesign.Muted)
        }
    }
    trusting?.let { bridge ->
        AlertDialog(
            onDismissRequest = { trusting = null },
            title = { Text(stringResource(R.string.pair_trust_host), color = MobileDesign.Ink) },
            text = {
                Text(
                    text = stringResource(R.string.pair_trust_instructions) + "\n\n" +
                        bridge.host.name + "\n" + bridge.host.id,
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    trusting = null
                    onPairDiscovered?.invoke(bridge)
                }) { Text(stringResource(R.string.pair_confirm_identity)) }
            },
            dismissButton = {
                TextButton(onClick = { trusting = null }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

/** The request is written; the owner still has to approve this exact device. */
@Composable
fun AwaitingOwnerScreen(
    hostName: String,
    requestID: String,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .padding(MobileDesign.PageInset),
        verticalArrangement = Arrangement.spacedBy(MobileDesign.SectionGap),
    ) {
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.pair_awaiting_owner, hostName), style = MaterialTheme.typography.titleLarge, color = MobileDesign.Ink)
        FloatingSurface(contentPadding = PaddingValues(16.dp)) {
            Text(stringResource(R.string.pair_awaiting_owner_note), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(10.dp))
            Text(
                text = requestID.take(8).uppercase(),
                style = MaterialTheme.typography.titleMedium,
                color = MobileDesign.Ink,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Button(
            onClick = onCancel,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Soft, contentColor = MobileDesign.Ink),
        ) { Text(stringResource(R.string.common_cancel)) }
    }
}

/** A stable error code with a readable sentence. */
@Composable
fun FailedScreen(code: String, message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .padding(MobileDesign.PageInset),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.pair_failed_title), style = MaterialTheme.typography.titleLarge, color = MobileDesign.Ink)
        Text(message, color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
        Text(code, style = MaterialTheme.typography.labelMedium, color = MobileDesign.Muted)
        Button(onClick = onRetry, shape = CircleShape, colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent)) {
            Text(stringResource(R.string.common_retry), color = MobileDesign.Canvas)
        }
    }
}
