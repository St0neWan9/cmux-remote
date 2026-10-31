package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** A model the agent's own configuration offers. */
data class ModelOption(val id: String, val label: String)

/** A pill that shows the current model and opens the models the agent offers. */
@Composable
fun ModelMenu(
    current: String?,
    options: List<ModelOption>,
    enabled: Boolean,
    onPick: (ModelOption) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember(enabled) { mutableStateOf(false) }
    Box(modifier) {
        Row(
            modifier = Modifier
                .background(MobileDesign.Soft, CircleShape)
                .clickable(enabled = enabled, onClick = { expanded = true })
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = current ?: stringResource(R.string.common_model),
                color = if (enabled) MobileDesign.Ink else MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
            )
            Icon(
                Icons.Rounded.ArrowDropDown,
                contentDescription = stringResource(R.string.common_select_model),
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = option.label,
                            color = if (option.id == current) MobileDesign.Accent else MobileDesign.Ink,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    },
                    onClick = {
                        expanded = false
                        onPick(option)
                    },
                )
            }
        }
    }
}

/** Renames a session; whitespace-only or unchanged names cannot be saved. */
@Composable
fun RenameDialog(
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var text by remember(initial) { mutableStateOf(initial) }
    val trimmed = text.trim()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.chat_rename_session), color = MobileDesign.Ink) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(stringResource(R.string.chat_session_name_placeholder), color = MobileDesign.Muted) },
                singleLine = true,
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(trimmed) },
                enabled = trimmed.isNotEmpty() && trimmed != initial.trim(),
            ) {
                Text(stringResource(R.string.common_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
            }
        },
    )
}

/** Shown above the composer when the Agent's terminal is gone but its session can be reopened. */
@Composable
fun ResumeBanner(onResume: () -> Unit, busy: Boolean, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MobileDesign.AccentSoft,
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.chat_resume_prompt),
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = onResume,
                enabled = !busy,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MobileDesign.Accent,
                    contentColor = MobileDesign.Canvas,
                ),
            ) {
                Text(stringResource(R.string.chat_reopen), style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}
