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
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.platform.testTag
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
import com.cmuxremote.mobile.ui.components.WorkingIndicator
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
    /** Per-Mac reachability, for the tab's status dot. */
    val hostReachable: Map<String, Boolean?> = emptyMap(),
    /** False when no Mac granted conversationRead; the list then has no readable state. */
    val canReadConversations: Boolean = true,
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
    /** Opens the Feed scoped to one Mac. */
    val onOpenFeedHost: ((String) -> Unit)? = null,
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

/**
 * The left drawer is the whole conversation tree, not just a workspace picker:
 * search and sort at the top, workspace groups with their sessions, then every
 * Mac with its own connection page.
 */
@Composable
fun DrawerContent(
    model: SessionListModel,
    actions: SessionListActions,
    onSelectSession: (SessionItem) -> Unit,
    onHostConnection: (String) -> Unit,
    closed: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var searching by remember { mutableStateOf(model.query.isNotBlank()) }
    var sortOpen by remember { mutableStateOf(false) }
    val selected = model.selectedID
    val otherTitle = stringResource(R.string.sessions_other)
    val query = model.query.trim()
    val filtered = model.sessions
        .filter { model.hostFilter == null || it.hostKey == null || it.hostKey == model.hostFilter }
        .filter {
            query.isEmpty() || it.title.contains(query, ignoreCase = true) ||
                it.agent.contains(query, ignoreCase = true) ||
                it.cwd.orEmpty().contains(query, ignoreCase = true)
        }
        .sortedWith(
            compareByDescending<SessionItem> { it.updatedAt?.toEpochMilli() ?: Long.MIN_VALUE }
                .thenByDescending { it.writable }
                .thenBy { it.title.lowercase() },
        )
    Column(modifier.background(MobileDesign.Canvas)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset).padding(top = 52.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.app_name), color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Box {
                Icon(
                    Icons.Rounded.MoreVert,
                    contentDescription = stringResource(R.string.sessions_sort),
                    tint = MobileDesign.Muted,
                    modifier = Modifier.size(22.dp).clickable { sortOpen = true },
                )
                DropdownMenu(expanded = sortOpen, onDismissRequest = { sortOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.sessions_sort_workspace)) },
                        trailingIcon = if (!model.sortByTime) ({ Icon(Icons.Rounded.Check, contentDescription = null) }) else null,
                        onClick = { sortOpen = false; actions.onSort(false) },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.sessions_sort_time)) },
                        trailingIcon = if (model.sortByTime) ({ Icon(Icons.Rounded.Check, contentDescription = null) }) else null,
                        onClick = { sortOpen = false; actions.onSort(true) },
                    )
                }
            }
            Icon(
                Icons.Rounded.Search,
                contentDescription = stringResource(R.string.common_search),
                tint = MobileDesign.Muted,
                modifier = Modifier.size(22.dp).clickable { searching = true },
            )
        }
        if (searching) {
            SessionSearchField(
                query = model.query,
                onChange = actions.onSearch,
                onClose = { searching = false; actions.onSearch("") },
                modifier = Modifier.padding(horizontal = MobileDesign.PageInset, vertical = 4.dp),
            )
        }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 12.dp)) {
            if (model.sortByTime) {
                items(filtered, key = { it.hostKey.orEmpty() + ":" + it.id }) { session ->
                    DrawerSessionRow(
                        session = session,
                        selected = session.hostKey.orEmpty() + ":" + session.id == selected,
                        showMac = model.hosts.size > 1,
                        onClick = { onSelectSession(session) },
                    )
                }
            } else {
                val grouped = filtered
                    .groupBy { (it.hostKey.orEmpty() + "|" + it.workspaceKey).lowercase() }
                    .values
                    .sortedByDescending { rows -> rows.maxOfOrNull { it.updatedAt?.toEpochMilli() ?: Long.MIN_VALUE } ?: Long.MIN_VALUE }
                grouped.forEach { rows ->
                    val workspaceID = rows.first().workspaceKey
                    val key = "drawer-" + rows.first().hostKey.orEmpty() + "-" + workspaceID
                    val open = !model.collapsed.contains(key)
                    val title = if (workspaceID.isEmpty()) {
                        otherTitle
                    } else {
                        model.workspaces.entries.firstOrNull { it.key.equals(workspaceID, true) }?.value
                            ?: rows.first().title
                    }
                    item(key = key) {
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { actions.onToggleGroup(key) }.padding(horizontal = 8.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                if (workspaceID.isEmpty()) Icons.Rounded.Schedule else Icons.Rounded.Computer,
                                contentDescription = null,
                                tint = MobileDesign.Muted,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(rows.size.toString(), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
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
                            DrawerSessionRow(
                                session = session,
                                selected = session.hostKey.orEmpty() + ":" + session.id == selected,
                                showMac = model.hosts.size > 1,
                                onClick = { onSelectSession(session) },
                            )
                        }
                    }
                }
            }
            if (filtered.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.sessions_no_matching),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 12.dp),
                    )
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = MobileDesign.PageInset, vertical = 8.dp)) {
            model.hosts.forEach { (id, name) ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onHostConnection(id) }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        Modifier.size(7.dp).background(
                            when (model.hostReachable[id]) {
                                true -> MobileDesign.Good
                                false -> MaterialTheme.colorScheme.error
                                null -> MobileDesign.Muted
                            },
                            androidx.compose.foundation.shape.CircleShape,
                        ),
                    )
                    Icon(Icons.Rounded.Computer, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
                    Text(name, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    Icon(
                        Icons.Rounded.Settings,
                        contentDescription = stringResource(R.string.sessions_connection),
                        tint = MobileDesign.Muted,
                        modifier = Modifier.size(16.dp).clickable { onHostConnection(id) },
                    )
                }
            }
            Text(
                stringResource(R.string.sessions_add_mac),
                color = MobileDesign.Accent,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.clickable { closed(); actions.onAddMac() }.padding(vertical = 8.dp),
            )
        }
    }
}

/** One conversation inside the drawer, indented under its workspace. */
@Composable
private fun DrawerSessionRow(
    session: SessionItem,
    selected: Boolean,
    showMac: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp)
            .background(if (selected) MobileDesign.AccentSoft else MobileDesign.Canvas, androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(session.title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                listOfNotNull(session.agent, session.hostName.takeIf { showMac }, session.age).filter { it.isNotBlank() }.joinToString(" · "),
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (session.working) WorkingIndicator(size = 12.dp)
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
    // Relative times re-read the clock, so "3m ago" becomes "4m ago" without a refresh.
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    androidx.compose.runtime.LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(30_000)
            now = System.currentTimeMillis()
        }
    }
    val query = model.query.trim()
    val filtered = model.sessions.filter { session ->
        (model.hostFilter == null || session.hostKey == null || session.hostKey == model.hostFilter) &&
            (model.workspaceFilter == null || session.workspaceKey.equals(model.workspaceFilter, ignoreCase = true)) &&
            (
                query.isEmpty() ||
                    session.title.contains(query, ignoreCase = true) ||
                    session.agent.contains(query, ignoreCase = true) ||
                    session.cwd.orEmpty().contains(query, ignoreCase = true)
                ) &&
            when (model.statusFilter) {
                // "Running" includes a writable session, as on the iPhone; read-only
                // is the absence of write access, including a resumable session.
                1 -> session.working || session.writable
                2 -> !session.writable
                else -> true
            }
    }
    // Newest first, writable before read-only, then by title; equal activity must
    // not depend on whatever order the Bridge happened to return.
    val ordered = filtered.sortedWith(
        compareByDescending<SessionItem> { it.updatedAt?.toEpochMilli() ?: Long.MIN_VALUE }
            .thenByDescending { it.writable }
            .thenBy { it.title.lowercase() },
    )
    val multipleHosts = model.hosts.size > 1
    val showMacSections = multipleHosts && !model.sortByTime
    // Workspace headings disappear once one workspace is explicitly selected.
    val showGroupHeadings = model.workspaceFilter == null && !model.sortByTime
    val recentTitle = stringResource(R.string.sessions_recent)
    val otherTitle = stringResource(R.string.sessions_other)
    // Mac order follows the saved list, not the alphabetical grouping map.
    val hostOrder = model.hosts.map { it.first } + ordered.mapNotNull { it.hostKey }.filter { it !in model.hosts.map { h -> h.first } }
    val byHost = ordered.groupBy { it.hostKey.orEmpty() }
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
                modifier = Modifier.testTag("sessions.list"),
                contentPadding = PaddingValues(horizontal = MobileDesign.PageInset, vertical = 8.dp),
                // The iPhone separates session groups by 24 points; only a short
                // window tightens the list.
                verticalArrangement = Arrangement.spacedBy(if (dense) 10.dp else MobileDesign.SectionGap),
            ) {
                if (model.loading && model.sessions.isEmpty()) {
                    item {
                        Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                            WorkingIndicator()
                        }
                    }
                }
                item {
                    MacTabs(
                        hosts = model.hosts,
                        selected = model.hostFilter,
                        reachable = model.hostReachable,
                        onSelect = actions.onHost,
                    )
                }
                // The reminder follows the selected Mac, never another Mac's queue.
                val visiblePending = model.pending.filter { model.hostFilter == null || it.hostID == model.hostFilter }
                val pendingCount = if (model.hostFilter == null) {
                    maxOf(visiblePending.size, model.pendingCount)
                } else {
                    visiblePending.size
                }
                if (pendingCount > 0) {
                    item {
                        PendingCard(
                            dense = dense,
                            count = pendingCount,
                            first = visiblePending.firstOrNull()?.title.orEmpty(),
                            onOpen = actions.onOpenFeed,
                            queues = visiblePending.groupBy { it.hostID }
                                .map { (id, items) -> Triple(id, items.first().hostName, items.size) },
                            onOpenHost = actions.onOpenFeedHost,
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
                if (!multipleHosts && !model.sortByTime && model.workspaceFilter == null && model.sessions.isNotEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.sessions_workspaces),
                            color = MobileDesign.Ink,
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
                if (model.sortByTime) {
                    // The iPhone's time order is flat; the Mac name travels in the row.
                    items(ordered, key = { it.hostKey.orEmpty() + ":" + it.id }) { session ->
                        SessionRow(
                            session = session,
                            selected = session.hostKey.orEmpty() + ":" + session.id == model.selectedID,
                            nowMillis = now,
                            showMac = multipleHosts && model.hostFilter == null,
                            onClick = { actions.onSelect(session) },
                        )
                    }
                } else {
                    val hostsToRender = if (showMacSections) hostOrder else listOf("")
                    hostsToRender.forEach { hostID ->
                        val hostRows = byHost[hostID].orEmpty()
                        if (hostRows.isEmpty()) return@forEach
                        if (showMacSections) {
                            val name = model.hosts.firstOrNull { it.first == hostID }?.second ?: hostRows.first().hostName.orEmpty()
                            val reached = model.hostReachable[hostID]
                            item(key = "mac-$hostID") {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Icon(Icons.Rounded.Computer, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(15.dp))
                                    Text(name, color = MobileDesign.Ink, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                                    Box(
                                        Modifier.size(6.dp).background(
                                            when (reached) {
                                                true -> MobileDesign.Good
                                                false -> MaterialTheme.colorScheme.error
                                                null -> MobileDesign.Muted
                                            },
                                            CircleShape,
                                        ),
                                    )
                                    if (reached == false) {
                                        Text(
                                            stringResource(R.string.sessions_unreachable),
                                            color = MaterialTheme.colorScheme.error,
                                            style = MaterialTheme.typography.labelMedium,
                                        )
                                    }
                                }
                            }
                        }
                        if (model.workspaceFilter != null || !showGroupHeadings) {
                            items(hostRows, key = { it.hostKey.orEmpty() + ":" + it.id }) { session ->
                                SessionRow(
                                    session = session,
                                    selected = session.hostKey.orEmpty() + ":" + session.id == model.selectedID,
                                    nowMillis = now,
                                    onClick = { actions.onSelect(session) },
                                )
                            }
                        } else {
                            val groupRows = hostRows.groupBy { it.workspaceKey.lowercase() }
                                .values
                                .sortedByDescending { rows -> rows.maxOfOrNull { it.updatedAt?.toEpochMilli() ?: Long.MIN_VALUE } ?: Long.MIN_VALUE }
                            groupRows.forEach { rows ->
                                val workspaceID = rows.firstOrNull()?.workspaceKey.orEmpty()
                                val unbound = workspaceID.isEmpty()
                                val title = if (unbound) {
                                    otherTitle
                                } else {
                                    model.workspaces.entries.firstOrNull { it.key.equals(workspaceID, true) }?.value
                                        ?: rows.firstOrNull()?.title
                                        ?: workspaceID
                                }
                                val key = "group-$hostID-$workspaceID"
                                val open = !model.collapsed.contains(key)
                                item(key = key) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth().clickable { actions.onToggleGroup(key) },
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Icon(
                                            if (unbound) Icons.Rounded.Schedule else Icons.Rounded.Computer,
                                            contentDescription = null,
                                            tint = MobileDesign.Muted,
                                            modifier = Modifier.size(17.dp),
                                        )
                                        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Spacer(Modifier.weight(1f))
                                        if (!unbound && actions.onStartInWorkspace != null) {
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
                                            nowMillis = now,
                                            modifier = Modifier.padding(start = 34.dp),
                                            onClick = { actions.onSelect(session) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                if (filtered.isEmpty() && !model.loading && model.error == null) {
                    item {
                        Text(
                            text = when {
                                !model.canReadConversations -> stringResource(R.string.sessions_no_permission)
                                model.sessions.isEmpty() -> stringResource(R.string.sessions_no_sessions)
                                else -> stringResource(R.string.sessions_no_matching)
                            },
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
                // The iPhone shows an error below a single Mac's list, not above it.
                if (model.error != null && !multipleHosts) {
                    item { Text(model.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
                }
            }
        }
        SessionFooter(dense = dense, hostName = model.hosts.firstOrNull()?.second.orEmpty(), onRefresh = actions.onRefresh)
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
private fun PendingCard(
    dense: Boolean = false,
    count: Int = 0,
    first: String = "",
    onOpen: () -> Unit = {},
    queues: List<Triple<String, String, Int>> = emptyList(),
    onOpenHost: ((String) -> Unit)? = null,
) {
    var menu by remember { mutableStateOf(false) }
    val perHost = queues.size > 1 && onOpenHost != null
    FloatingSurface(contentPadding = PaddingValues(horizontal = 14.dp, vertical = if (dense) 10.dp else 14.dp)) {
        Row(
            modifier = Modifier.clickable { if (perHost) menu = true else onOpen() },
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
        // Several Macs each have their own queue; the reminder opens the one chosen.
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            queues.filter { it.third > 0 }.forEach { (id, name, hostCount) ->
                DropdownMenuItem(
                    text = { Text("$name · $hostCount", color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium) },
                    onClick = { menu = false; onOpenHost?.invoke(id) },
                )
            }
        }
    }
}

@Composable
private fun SessionFooter(dense: Boolean = false, hostName: String = "", onRefresh: () -> Unit = {}) {
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
            if (hostName.isNotBlank()) {
                StatusDot()
                Icon(Icons.Rounded.Computer, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(16.dp))
                Text(hostName, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onRefresh) {
                Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.common_refresh), tint = MobileDesign.Muted, modifier = Modifier.size(18.dp))
            }
        }
    }
}
