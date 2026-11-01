package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** The list's search field, which takes the whole header while it is open. */
@Composable
fun SessionSearchField(
    query: String,
    onChange: (String) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .background(MobileDesign.Soft, CircleShape)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Rounded.Search, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(18.dp))
            BasicTextField(
                value = query,
                onValueChange = onChange,
                modifier = Modifier.weight(1f).focusRequester(focus),
                singleLine = true,
                textStyle = TextStyle(color = MobileDesign.Ink, fontSize = 15.sp),
                cursorBrush = SolidColor(MobileDesign.Accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { keyboard?.hide() }),
                decorationBox = { inner ->
                    Box {
                        if (query.isEmpty()) Text(stringResource(R.string.sessions_search_placeholder), color = MobileDesign.Muted, fontSize = 15.sp)
                        inner()
                    }
                },
            )
        }
        IconButton(onClick = { onClose() }) {
            Icon(Icons.Rounded.Close, contentDescription = stringResource(R.string.sessions_close_search), tint = MobileDesign.Ink)
        }
    }
}

/** The title's menu: sort, decisions, refresh, a new conversation and adding a Mac. */
@Composable
fun SessionTitleMenu(
    sortByTime: Boolean,
    pendingCount: Int,
    canStart: Boolean,
    onSort: (Boolean) -> Unit,
    onFeed: () -> Unit,
    onRefresh: () -> Unit,
    onStart: () -> Unit,
    onAddMac: () -> Unit,
    onConnection: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Text(
            text = "Cmux",
            color = MobileDesign.Ink,
            fontSize = 22.sp,
            modifier = Modifier
                .clickable { open = true }
                .padding(vertical = 6.dp, horizontal = 2.dp),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = {
                    Text(
                        if (sortByTime) stringResource(R.string.sessions_sort_by_time)
                        else stringResource(R.string.sessions_sort_by_workspace),
                    )
                },
                onClick = { onSort(!sortByTime); open = false },
            )
            DropdownMenuItem(
                text = {
                    Text(
                        if (pendingCount > 0) stringResource(R.string.sessions_pending_count, pendingCount)
                        else stringResource(R.string.sessions_pending),
                    )
                },
                onClick = { onFeed(); open = false },
            )
            DropdownMenuItem(text = { Text(stringResource(R.string.common_refresh)) }, onClick = { onRefresh(); open = false })
            if (canStart) {
                DropdownMenuItem(text = { Text(stringResource(R.string.sessions_new_session)) }, onClick = { onStart(); open = false })
            }
            DropdownMenuItem(text = { Text(stringResource(R.string.sessions_add_mac)) }, onClick = { onAddMac(); open = false })
            DropdownMenuItem(text = { Text(stringResource(R.string.sessions_connection_details)) }, onClick = { onConnection(); open = false })
        }
    }
}

/** The Mac tabs: one capsule per approved Mac, plus "all" when there are several. */
@Composable
fun MacTabs(
    hosts: List<Pair<String, String>>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (hosts.size > 1) {
            Capsule(text = stringResource(R.string.sessions_all_macs), selected = selected == null) { onSelect(null) }
        }
        hosts.forEach { (id, name) ->
            Capsule(text = name, selected = hosts.size == 1 || selected == id) { onSelect(id) }
        }
    }
}

@Composable
private fun Capsule(text: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .background(if (selected) MobileDesign.Soft else MobileDesign.Canvas, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).background(MobileDesign.Good, CircleShape))
        Text(text, color = if (selected) MobileDesign.Ink else MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A workspace filter capsule: the menu lists every workspace the device may read. */
@Composable
fun WorkspaceFilterCapsule(
    workspaces: List<Pair<String, String>>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Text(
            text = workspaces.firstOrNull { it.first == selected }?.second ?: stringResource(R.string.sessions_all_workspaces),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier
                .background(MobileDesign.Canvas, RoundedCornerShape(50))
                .clickable { open = true }
                .padding(horizontal = 12.dp, vertical = 8.dp),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.sessions_all_workspaces)) }, onClick = { onSelect(null); open = false })
            workspaces.forEach { (id, title) ->
                DropdownMenuItem(text = { Text(title) }, onClick = { onSelect(id); open = false })
            }
        }
    }
}
