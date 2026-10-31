package com.cmuxremote.mobile.ui

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Laptop
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** Public trust details and the capabilities the Mac has approved for this device. */
data class ConnectionInfo(
    val hostID: String? = null,
    val name: String,
    val endpoint: String,
    val identity: String?,
    val certificate: String?,
    val protocolName: String?,
    val reachable: Boolean,
    val capabilities: List<String>,   // raw capability names
    val overRelay: Boolean,
    val keystoreBacking: String?,     // "keystore" | "plain"
    val error: String?,
)

private val CapabilityOrder = listOf(
    "workspaceRead",
    "conversationRead",
    "projectRead",
    "conversationControl",
    "feedRead",
    "feedReply",
    "conversationStart",
    "terminalRead",
    "terminalInput",
)

/** Same order as the shared capability list, with anything newer kept after it. */
private fun orderedCapabilities(capabilities: List<String>): List<String> {
    val granted = capabilities.toSet()
    val known = CapabilityOrder.filter { it in granted }
    val unknown = capabilities.filter { it !in CapabilityOrder }.distinct()
    return known + unknown
}

@Composable
private fun capabilityLabel(raw: String): String = when (raw) {
    "workspaceRead" -> stringResource(R.string.connection_cap_workspace_read)
    "conversationRead" -> stringResource(R.string.connection_cap_conversation_read)
    "projectRead" -> stringResource(R.string.connection_cap_project_read)
    "conversationControl" -> stringResource(R.string.connection_cap_conversation_control)
    "feedRead" -> stringResource(R.string.connection_cap_feed_read)
    "feedReply" -> stringResource(R.string.connection_cap_feed_reply)
    "conversationStart" -> stringResource(R.string.connection_cap_conversation_start)
    "terminalRead" -> stringResource(R.string.connection_cap_terminal_read)
    "terminalInput" -> stringResource(R.string.connection_cap_terminal_input)
    else -> raw
}

@Composable
fun ConnectionDetailScreen(
    info: ConnectionInfo,
    loading: Boolean,
    backgroundSync: Boolean,
    onBackgroundSync: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onRemove: () -> Unit,
    onDiagnostics: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmRemove by remember { mutableStateOf(false) }

    Column(
        modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
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
                stringResource(R.string.connection_title),
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleMedium,
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
            HostCard(info = info, loading = loading)

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    DetailRow(stringResource(R.string.connection_endpoint), info.endpoint)
                    info.protocolName?.let { DetailRow(stringResource(R.string.connection_protocol), it) }
                    info.identity?.let { DetailRow(stringResource(R.string.connection_host_identity), it, monospaced = true) }
                    info.certificate?.let { DetailRow(stringResource(R.string.connection_certificate_fingerprint), it, monospaced = true) }
                }
            }

            PermissionsCard(capabilities = info.capabilities)

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                Text(
                    stringResource(R.string.connection_transport),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    if (info.overRelay) stringResource(R.string.connection_transport_relay)
                    else stringResource(R.string.connection_transport_direct),
                    color = MobileDesign.Ink,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            if (info.keystoreBacking != null) {
                FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(
                            Icons.Rounded.Key,
                            contentDescription = null,
                            tint = MobileDesign.Muted,
                            modifier = Modifier.size(17.dp),
                        )
                        Text(
                            stringResource(R.string.connection_key),
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        if (info.keystoreBacking == "keystore") stringResource(R.string.connection_keystore_protected)
                        else stringResource(R.string.connection_keystore_plain),
                        color = MobileDesign.Ink,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            FloatingSurface(contentPadding = PaddingValues(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.connection_background_sync),
                        color = MobileDesign.Ink,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = backgroundSync,
                        onCheckedChange = onBackgroundSync,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = MobileDesign.Canvas,
                            checkedTrackColor = MobileDesign.Accent,
                            uncheckedThumbColor = MobileDesign.Canvas,
                            uncheckedTrackColor = MobileDesign.Soft,
                            uncheckedBorderColor = MobileDesign.Muted,
                        ),
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.connection_background_sync_note),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(MobileDesign.RowGap)) {
                ActionButton(text = stringResource(R.string.common_refresh), onClick = onRefresh, enabled = !loading)
                ActionButton(text = stringResource(R.string.connection_diagnostics), onClick = onDiagnostics)
                ActionButton(
                    text = stringResource(R.string.connection_remove_mac),
                    onClick = { confirmRemove = true },
                    destructive = true,
                )
                Text(
                    stringResource(R.string.connection_remove_hint),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }

    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text(stringResource(R.string.connection_remove_title), color = MobileDesign.Ink) },
            text = { Text(stringResource(R.string.connection_remove_hint), color = MobileDesign.Muted) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmRemove = false
                        onRemove()
                    },
                ) {
                    Text(stringResource(R.string.common_remove), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemove = false }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

@Composable
private fun HostCard(info: ConnectionInfo, loading: Boolean) {
    FloatingSurface(contentPadding = PaddingValues(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(
                Icons.Rounded.Laptop,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(22.dp),
            )
            Text(
                info.name,
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
            )
        }
        if (loading) {
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                WorkingIndicator()
                Text(
                    stringResource(R.string.connection_connecting),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        if (info.reachable) {
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(
                    Icons.Rounded.VerifiedUser,
                    contentDescription = null,
                    tint = MobileDesign.Good,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    stringResource(R.string.connection_reachable),
                    color = MobileDesign.Good,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        if (info.error != null) {
            Spacer(Modifier.height(12.dp))
            Text(
                info.error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun DetailRow(title: String, value: String, monospaced: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title,
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
        )
        SelectionContainer {
            Text(
                value,
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = if (monospaced) FontFamily.Monospace else null,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PermissionsCard(capabilities: List<String>) {
    FloatingSurface(contentPadding = PaddingValues(16.dp)) {
        Text(
            stringResource(R.string.connection_permissions_title),
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.height(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            orderedCapabilities(capabilities).forEach { raw ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(
                        Icons.Rounded.Check,
                        contentDescription = null,
                        tint = MobileDesign.Good,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        capabilityLabel(raw),
                        color = MobileDesign.Ink,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(
            stringResource(R.string.connection_owner_managed),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
private fun ActionButton(
    text: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    destructive: Boolean = false,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        border = BorderStroke(0.5.dp, MobileDesign.Line),
        modifier = Modifier.fillMaxWidth().heightIn(min = MobileDesign.Control),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 3.dp, pressedElevation = 1.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MobileDesign.Canvas,
            contentColor = if (destructive) MaterialTheme.colorScheme.error else MobileDesign.Ink,
            disabledContainerColor = MobileDesign.Canvas,
            disabledContentColor = MobileDesign.Muted,
        ),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
