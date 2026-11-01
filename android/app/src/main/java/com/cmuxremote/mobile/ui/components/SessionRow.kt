package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.model.SessionItem
import com.cmuxremote.mobile.model.SessionTrailing
import com.cmuxremote.mobile.ui.theme.MobileDesign

@Composable
fun SessionRow(
    session: SessionItem,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    /** The list's clock, refreshed periodically so a relative time does not go stale. */
    nowMillis: Long = System.currentTimeMillis(),
    /** Several Macs are listed together, so the row names its own. */
    showMac: Boolean = false,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val meta = buildList {
        add(session.agent)
        if (showMac && !session.hostName.isNullOrBlank()) add(session.hostName)
        add(relativeAge(session.updatedAt, session.age, nowMillis, context))
        when (session.trailing) {
            SessionTrailing.Resumable -> add(context.getString(R.string.common_resumable))
            SessionTrailing.Locked -> add(context.getString(R.string.common_read_only))
            else -> Unit
        }
    }.filter { it.isNotBlank() }.joinToString("  ·  ")
    Row(
        modifier = modifier
            .fillMaxWidth()
            .testTag("session." + session.id)
            .clip(RoundedCornerShape(14.dp))
            .background(if (selected) MobileDesign.AccentSoft else MobileDesign.Canvas)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                text = session.title,
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = meta,
                color = MobileDesign.Muted,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        // A running row spins; every other row is a page, so it carries a chevron.
        if (session.trailing == SessionTrailing.Working) {
            WorkingIndicator()
        } else {
            Icon(
                Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** A localized relative age; the stored label is a fallback when the timestamp is malformed. */
private fun relativeAge(
    updatedAt: java.time.Instant?,
    stored: String,
    nowMillis: Long,
    context: android.content.Context,
): String {
    val instant = updatedAt ?: return stored
    // The platform's relative formatter covers every range and the reader's locale,
    // instead of four hand-written buckets.
    return android.text.format.DateUtils.getRelativeTimeSpanString(
        instant.toEpochMilli(),
        nowMillis,
        android.text.format.DateUtils.MINUTE_IN_MILLIS,
        android.text.format.DateUtils.FORMAT_ABBREV_RELATIVE,
    ).toString()
}
