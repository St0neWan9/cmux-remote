package com.cmuxremote.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.data.FeedItem
import com.cmuxremote.mobile.model.SessionItem
import com.cmuxremote.mobile.model.SessionTrailing
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.components.Pill
import com.cmuxremote.mobile.ui.components.SessionRow
import com.cmuxremote.mobile.ui.components.StatusDot
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** Everything the list needs to render, independent of how it is hosted. */
data class SessionListModel(
    val sessions: List<SessionItem>,
    val hosts: List<Pair<String, String>> = emptyList(),
    val hostFilter: String? = null,
    val workspaces: Map<String, String> = emptyMap(),
    val workspaceFilter: String? = null,
    val query: String = "",
    val sortByTime: Boolean = false,
    val statusFilter: Int = 0,
    val collapsed: Set<String> = emptySet(),
    val pending: List<FeedItem> = emptyList(),
    /** Pending count from the last background pass, when no live list is loaded yet. */
    val pendingCount: Int = 0,
    val loading: Boolean = false,
    val error: String? = null,
    val canStart: Boolean = false,
    val selectedID: String? = null,
)

/** The interactions the list offers; each one is owned by the shell. */
data class SessionListActions(
    val onSelect: (SessionItem) -> Unit = {},
    val onOpenFeed: () -> Unit = {},
    val onStart: (() -> Unit)? = null,
    /** Starts a conversation directly in one workspace. */
    val onStartInWorkspace: ((String) -> Unit)? = null,
    val onRefresh: () -> Unit = {},
    val onAddMac: () -> Unit = {},
    val onSearch: (String) -> Unit = {},
    val onSort: (Boolean) -> Unit = {},
    val onHost: (String?) -> Unit = {},
    val onWorkspace: (String?) -> Unit = {},
    val onStatus: (Int) -> Unit = {},
    val onToggleGroup: (String) -> Unit = {},
    val onConnection: () -> Unit = {},
    val onOpenSidebar: () -> Unit = {},
)

@Composable
fun SessionListScreen(
    model: SessionListModel,
    actions: SessionListActions,
    modifier: Modifier = Modifier,
    dense: Boolean = false,
    compact: Boolean = true,
) {
    SessionListContent(model, actions, modifier.fillMaxSize(), dense = dense, compact = compact)
}

/** The left drawer's tree: every workspace with its conversation count. */
@Composable
fun DrawerContent(
    hostName: String,
    workspaces: List<Pair<String, String>>,
    sessions: List<SessionItem>,
    selectedWorkspace: String?,
    onWorkspace: (String?) -> Unit,
    onConnection: () -> Unit,
    onAddMac: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.background(MobileDesign.Canvas)) {
        Text(
            stringResource(R.string.sessions_workspaces),
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(horizontal = MobileDesign.PageInset).padding(top = 52.dp, bottom = 16.dp),
        )
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = MobileDesign.PageInset)) {
            item {
                DrawerRow(
                    title = stringResource(R.string.sessions_all_workspaces),
                    count = sessions.size,
                    selected = selectedWorkspace == null,
                    onClick = { onWorkspace(null) },
                )
            }
            items(workspaces, key = { it.first }) { (id, title) ->
                DrawerRow(
                    title = title,
                    count = sessions.count { it.workspaceKey == id },
                    selected = selectedWorkspace == id,
                    onClick = { onWorkspace(id) },
                )
            }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onConnection).padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                StatusDot()
                Icon(Icons.Rounded.Computer, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
                Text(hostName, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                stringResource(R.string.sessions_add_mac),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.clickable(onClick = onAddMac).padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun DrawerRow(title: String, count: Int, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (selected) MobileDesign.AccentSoft else MobileDesign.Canvas, androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Rounded.Folder, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(count.toString(), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
fun SessionBrowserPane(
    model: SessionListModel,
    actions: SessionListActions,
    modifier: Modifier = Modifier,
) {
    SessionListContent(model, actions, modifier.fillMaxHeight(), dense = false, compact = false)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionListContent(
    model: SessionListModel,
    actions: SessionListActions,
    modifier: Modifier,
    dense: Boolean,
    compact: Boolean,
) {
    var searching by remember { mutableStateOf(false) }
    val filtered = model.sessions.filter { session ->
        (model.hostFilter == null || session.hostKey == null || session.hostKey == model.hostFilter) &&
            (model.workspaceFilter == null || session.workspaceKey == model.workspaceFilter) &&
            (model.query.isBlank() || session.title.contains(model.query, ignoreCase = true) || session.agent.contains(model.query, ignoreCase = true)) &&
            when (model.statusFilter) {
                1 -> session.trailing == SessionTrailing.Working
                2 -> session.trailing == SessionTrailing.Locked
                else -> true
            }
    }
    // Time order flattens the groups; workspace order keeps them, newest activity first.
    val ordered = if (model.sortByTime) filtered.sortedByDescending { it.updatedAt } else filtered
    val groups: Map<String, List<SessionItem>> = if (model.sortByTime) {
        mapOf(stringResource(R.string.sessions_recent) to ordered)
    } else {
        ordered.groupBy { model.workspaces[it.workspaceKey] ?: it.workspaceKey }
    }
    Column(modifier.background(MobileDesign.Canvas)) {
        if (searching) {
            SessionSearchField(
                query = model.query,
                onChange = actions.onSearch,
                onClose = { searching = false; actions.onSearch("") },
                modifier = Modifier.padding(horizontal = MobileDesign.PageInset, vertical = 8.dp),
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                if (compact) {
                    IconButton(onClick = actions.onOpenSidebar) {
                        Icon(Icons.Rounded.Menu, contentDescription = stringResource(R.string.common_sidebar), tint = MobileDesign.Ink)
                    }
                }
                SessionTitleMenu(
                    sortByTime = model.sortByTime,
                    pendingCount = maxOf(model.pending.size, model.pendingCount),
                    canStart = model.canStart,
                    onSort = actions.onSort,
                    onFeed = actions.onOpenFeed,
                    onRefresh = actions.onRefresh,
                    onStart = { actions.onStart?.invoke() },
                    onAddMac = actions.onAddMac,
                    onConnection = actions.onConnection,
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { searching = true }) {
                    Icon(Icons.Rounded.Search, contentDescription = stringResource(R.string.common_search), tint = MobileDesign.Ink)
                }
                if (actions.onStart != null) {
                    IconButton(onClick = { actions.onStart?.invoke() }) {
                        Icon(Icons.Rounded.Add, contentDescription = stringResource(R.string.sessions_new_session), tint = MobileDesign.Ink)
                    }
                }
            }
        }
        PullToRefreshBox(isRefreshing = model.loading, onRefresh = actions.onRefresh, modifier = Modifier.weight(1f)) {
            LazyColumn(
                contentPadding = PaddingValues(horizontal = MobileDesign.PageInset, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(if (dense) 10.dp else 16.dp),
            ) {
                item { MacTabs(hosts = model.hosts, selected = model.hostFilter, onSelect = actions.onHost) }
                val pendingCount = maxOf(model.pending.size, model.pendingCount)
                if (pendingCount > 0) {
                    item {
                        PendingCard(
                            dense = dense,
                            count = pendingCount,
                            first = model.pending.firstOrNull()?.title.orEmpty(),
                            onOpen = actions.onOpenFeed,
                        )
                    }
                }
                item {
                    WorkspaceFilterCapsule(
                        workspaces = model.workspaces.map { (id, title) -> id to title },
                        selected = model.workspaceFilter,
                        onSelect = actions.onWorkspace,
                    )
                }
                item {
                    FilterChips(model.statusFilter, actions.onStatus)
                }
                // The pull-to-refresh indicator already answers "is this loading";
                // a second spinner in the list drew two at once.
                if (model.error != null) {
                    item { Text(model.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
                }
                groups.forEach { (title, rows) ->
                    val key = "group-" + title
                    val open = !model.collapsed.contains(key)
                    val workspaceID = rows.firstOrNull()?.workspaceKey.orEmpty()
                    item(key = key) {
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { actions.onToggleGroup(key) },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Rounded.Folder, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(17.dp))
                            Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Spacer(Modifier.weight(1f))
                            if (workspaceID.isNotEmpty() && actions.onStartInWorkspace != null) {
                                IconButton(onClick = { actions.onStartInWorkspace?.invoke(workspaceID) }) {
                                    Icon(
                                        Icons.Rounded.Add,
                                        contentDescription = stringResource(R.string.sessions_new_session),
                                        tint = MobileDesign.Muted,
                                        modifier = Modifier.size(17.dp),
                                    )
                                }
                            }
                            Icon(
                                if (open) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.ChevronRight,
                                contentDescription = if (open) stringResource(R.string.common_collapse) else stringResource(R.string.common_expand),
                                tint = MobileDesign.Muted,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    }
                    if (open) {
                        items(rows, key = { it.hostKey.orEmpty() + ":" + it.id }) { session ->
                            SessionRow(
                                session = session,
                                selected = session.hostKey.orEmpty() + ":" + session.id == model.selectedID,
                                onClick = { actions.onSelect(session) },
                            )
                        }
                    }
                }
                if (filtered.isEmpty() && !model.loading && model.error == null) {
                    item {
                        Text(
                            text = if (model.sessions.isEmpty()) stringResource(R.string.sessions_no_sessions)
                            else stringResource(R.string.sessions_no_matching),
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
        }
        SessionFooter(dense = dense, hostName = model.hosts.firstOrNull()?.second ?: "Studio", onRefresh = actions.onRefresh)
    }
}

@Composable
private fun FilterChips(selected: Int, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        listOf(
            stringResource(R.string.sessions_filter_all),
            stringResource(R.string.sessions_filter_working),
            stringResource(R.string.sessions_filter_read_only),
        ).forEachIndexed { index, label ->
            Pill(text = label, selected = index == selected, onClick = { onSelect(index) })
        }
    }
}

@Composable
private fun PendingCard(dense: Boolean = false, count: Int = 0, first: String = "", onOpen: () -> Unit = {}) {
    FloatingSurface(contentPadding = PaddingValues(horizontal = 14.dp, vertical = if (dense) 10.dp else 14.dp)) {
        Row(
            modifier = Modifier.clickable(onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier.size(if (dense) 28.dp else 34.dp).background(MobileDesign.AccentSoft, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(count.toString(), color = MobileDesign.Accent, fontWeight = FontWeight.SemiBold)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.sessions_pending_items, count), color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                if (!dense && first.isNotBlank()) {
                    Text(first, color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun SessionFooter(dense: Boolean = false, hostName: String = "Studio", onRefresh: () -> Unit = {}) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MobileDesign.Canvas)
            .padding(horizontal = MobileDesign.PageInset, vertical = if (dense) 4.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            StatusDot()
            Icon(Icons.Rounded.Computer, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
            Text(hostName, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onRefresh) {
                Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.common_refresh), tint = MobileDesign.Muted, modifier = Modifier.size(18.dp))
            }
        }
    }
}
