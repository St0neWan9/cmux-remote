package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

@Composable
fun Pill(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    selected: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val shape = CircleShape
    Row(
        modifier = modifier
            .background(if (selected) MobileDesign.Ink else MobileDesign.Soft, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (selected) MobileDesign.Canvas else MobileDesign.Muted,
                modifier = Modifier.size(15.dp),
            )
        }
        Text(
            text = text,
            color = if (selected) MobileDesign.Canvas else MobileDesign.Ink,
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
fun StatusDot(modifier: Modifier = Modifier) {
    Spacer(
        modifier = modifier
            .size(7.dp)
            .background(MobileDesign.Good, CircleShape),
    )
}

@Composable
fun SectionHeader(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    collapsed: Boolean = false,
) {
    Row(
        modifier = modifier.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MobileDesign.Muted, modifier = Modifier.size(17.dp))
        Text(
            text = title,
            color = MobileDesign.Ink,
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(Modifier.weight(1f))
        Icon(
            Icons.Rounded.ChevronRight,
            contentDescription = if (collapsed) stringResource(R.string.common_expand) else stringResource(R.string.common_collapse),
            tint = MobileDesign.Muted,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
fun FolderRow(title: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Rounded.Folder,
            contentDescription = null,
            tint = MobileDesign.Muted,
            modifier = Modifier.size(17.dp),
        )
        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun SpacerWidth(width: Int) {
    Spacer(Modifier.width(width.dp))
}
