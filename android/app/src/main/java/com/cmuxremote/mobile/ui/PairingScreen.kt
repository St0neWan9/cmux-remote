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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.KeyboardArrowDown
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ShellState
import com.cmuxremote.mobile.bridge.DiscoveredBridge
import com.cmuxremote.mobile.protocol.EnrollmentBootstrap
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign

/**
 * Adding a Mac follows the iPhone's page order: scan, nearby Macs, relays, then
 * the advanced paste. The pairing code no longer has a field of its own; a link
 * or the Mac's signed enrollment JSON is pasted under Advanced.
 */
@Composable
fun PairingScreen(
    state: ShellState.Pairing,
    onPair: (String) -> Unit,
    onRetrySaved: () -> Unit,
    onScan: (() -> Unit)? = null,
    discovered: List<DiscoveredBridge> = emptyList(),
    approvedHostIDs: Set<String> = emptySet(),
    onPairDiscovered: ((DiscoveredBridge) -> Unit)? = null,
    relayOrigins: List<String> = emptyList(),
    relayHosts: List<EnrollmentBootstrap> = emptyList(),
    relayLoading: Boolean = false,
    relayError: String? = null,
    onAddRelay: (String) -> Unit = {},
    onRemoveRelay: (String) -> Unit = {},
    onRefreshRelay: (() -> Unit)? = null,
    onPairListed: ((EnrollmentBootstrap) -> Unit)? = null,
    onBack: (() -> Unit)? = null,
) {
    var relayDraft by remember { mutableStateOf("") }
    var advanced by remember { mutableStateOf(false) }
    var importText by remember { mutableStateOf("") }
    var trust by remember { mutableStateOf<TrustTarget?>(null) }

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

        if (onScan != null) {
            Button(
                onClick = onScan,
                enabled = !state.busy,
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth().height(MobileDesign.Control),
                colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
            ) {
                Icon(Icons.Rounded.QrCodeScanner, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.pair_scan), color = MobileDesign.Canvas)
            }
            Text(
                stringResource(R.string.pair_scan_instructions),
                style = MaterialTheme.typography.labelMedium,
                color = MobileDesign.Muted,
            )
        }

        FloatingSurface(contentPadding = PaddingValues(16.dp)) {
            SectionTitle(stringResource(R.string.pair_nearby))
            Spacer(Modifier.height(8.dp))
            if (discovered.isEmpty()) {
                Text(stringResource(R.string.pair_searching), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            }
            discovered.forEach { bridge ->
                HostRow(
                    icon = Icons.Rounded.Laptop,
                    name = bridge.host.name,
                    id = bridge.host.id,
                    approved = bridge.host.id in approvedHostIDs,
                    onClick = { trust = TrustTarget(bridge.host.name, bridge.host.id) { onPairDiscovered?.invoke(bridge) } },
                )
            }
        }

        FloatingSurface(contentPadding = PaddingValues(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(stringResource(R.string.pair_relay), modifier = Modifier.weight(1f))
                if (onRefreshRelay != null) {
                    TextButton(onClick = onRefreshRelay, enabled = !relayLoading) {
                        Text(stringResource(R.string.common_refresh), color = MobileDesign.Accent)
                    }
                }
            }
            if (relayOrigins.isEmpty()) {
                Text(stringResource(R.string.pair_relay_hint), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
            } else {
                if (relayLoading && relayHosts.isEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        WorkingIndicator(size = 14.dp)
                        Text(stringResource(R.string.pair_relay_loading), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                relayHosts.forEach { entry ->
                    HostRow(
                        icon = Icons.Rounded.Cloud,
                        name = entry.host.name,
                        id = entry.host.id,
                        approved = entry.host.id in approvedHostIDs,
                        onClick = { trust = TrustTarget(entry.host.name, entry.host.id) { onPairListed?.invoke(entry) } },
                    )
                }
                if (!relayLoading && relayHosts.isEmpty() && relayError == null) {
                    Text(stringResource(R.string.pair_relay_empty), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
                }
                if (relayError != null) {
                    Text(relayError, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                }
                Spacer(Modifier.height(4.dp))
                relayOrigins.forEach { origin ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = origin,
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = stringResource(R.string.pair_relay_remove),
                            color = MobileDesign.Accent,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.clickable { onRemoveRelay(origin) }.padding(vertical = 4.dp),
                        )
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = relayDraft,
                onValueChange = { relayDraft = it.trim() },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("https://relay.example.com", color = MobileDesign.Muted) },
                label = { Text(stringResource(R.string.pair_relay_address), color = MobileDesign.Muted) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                singleLine = true,
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { val value = relayDraft; relayDraft = ""; onAddRelay(value) },
                enabled = relayDraft.isNotBlank() && !relayLoading,
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Accent),
            ) {
                Text(stringResource(R.string.pair_relay_add), color = MobileDesign.Canvas)
            }
        }

        FloatingSurface(contentPadding = PaddingValues(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable { advanced = !advanced },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SectionTitle(stringResource(R.string.pair_advanced), modifier = Modifier.weight(1f))
                Icon(
                    if (advanced) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.ChevronRight,
                    contentDescription = null,
                    tint = MobileDesign.Muted,
                    modifier = Modifier.size(18.dp),
                )
            }
            if (advanced) {
                Spacer(Modifier.height(10.dp))
                Text(
                    stringResource(R.string.pair_import_note),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = importText,
                    onValueChange = { importText = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.pair_import_placeholder), color = MobileDesign.Muted) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                    minLines = 2,
                    maxLines = 5,
                )
                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = {
                        val value = importText.trim()
                        importText = ""
                        onPair(value)
                    },
                    enabled = importText.isNotBlank() && !state.busy,
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = MobileDesign.Ink, contentColor = MobileDesign.Canvas),
                ) {
                    Text(stringResource(R.string.pair_import))
                }
            }
        }

        if (state.error != null) {
            Text(state.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }
        if (state.notice != null) {
            Text(state.notice, color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
        }
        TextButton(onClick = onRetrySaved) {
            Text(stringResource(R.string.pair_retry_saved), color = MobileDesign.Muted)
        }
    }

    trust?.let { target ->
        AlertDialog(
            onDismissRequest = { trust = null },
            title = { Text(stringResource(R.string.pair_trust_host), color = MobileDesign.Ink) },
            text = {
                Text(
                    text = stringResource(R.string.pair_trust_instructions) + "\n\n" + target.name + "\n" + target.id,
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    trust = null
                    target.confirm()
                }) { Text(stringResource(R.string.pair_confirm_identity)) }
            },
            dismissButton = {
                TextButton(onClick = { trust = null }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

private data class TrustTarget(val name: String, val id: String, val confirm: () -> Unit)

@Composable
private fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium, modifier = modifier)
}

@Composable
private fun HostRow(
    icon: ImageVector,
    name: String,
    id: String,
    approved: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !approved, onClick = onClick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            if (approved) Icons.Rounded.CheckCircle else icon,
            contentDescription = null,
            tint = if (approved) MobileDesign.Good else MobileDesign.Muted,
            modifier = Modifier.size(18.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(id.take(16).uppercase(), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
        }
        if (approved) {
            Text(stringResource(R.string.pair_approved), color = MobileDesign.Good, style = MaterialTheme.typography.labelMedium)
        }
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
