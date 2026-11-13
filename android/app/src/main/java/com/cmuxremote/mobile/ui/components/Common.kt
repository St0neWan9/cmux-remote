package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.runtime.getValue
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.graphics.graphicsLayer
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
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
    val isSelected = selected
    Row(
        modifier = modifier
            .semantics { this.selected = isSelected }
            .then(if (selected) Modifier.shadow(3.dp, shape, clip = false) else Modifier)
            // The pressed tint follows the capsule rather than filling its square bounds.
            .clip(shape)
            .background(MobileDesign.Canvas, shape)
            .border(0.5.dp, MobileDesign.Line, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (selected) MobileDesign.Accent else MobileDesign.Muted,
                modifier = Modifier.size(15.dp),
            )
        }
        Text(
            text = text,
            color = if (selected) MobileDesign.Accent else MobileDesign.Ink,
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
    val state = stringResource(if (collapsed) R.string.common_expand else R.string.common_collapse)
    Row(
        modifier = modifier
            .padding(vertical = 4.dp)
            .semantics {
                heading()
                stateDescription = state
            },
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

/**
 * The iPhone's capsule action: white by default, accent when prominent, the
 * destructive label in red, and 0.65 press / 0.45 disabled opacity.
 */
@Composable
fun FloatingAction(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    destructive: Boolean = false,
    enabled: Boolean = true,
) {
    val interaction = androidx.compose.foundation.interaction.MutableInteractionSource()
    val pressed by interaction.collectIsPressedAsState()
    val alpha = if (!enabled) 0.45f else if (pressed) 0.65f else 1f
    androidx.compose.material3.Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        border = androidx.compose.foundation.BorderStroke(0.5.dp, MobileDesign.Line),
        elevation = androidx.compose.material3.ButtonDefaults.buttonElevation(
            defaultElevation = if (prominent && enabled) 3.dp else 2.dp,
            pressedElevation = 1.dp,
        ),
        interactionSource = interaction,
        colors = androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = if (prominent && enabled) MobileDesign.Accent else MobileDesign.Canvas,
            contentColor = when {
                destructive -> MaterialTheme.colorScheme.error
                prominent -> MobileDesign.Canvas
                else -> MobileDesign.Ink
            },
            disabledContainerColor = MobileDesign.Canvas,
            disabledContentColor = MobileDesign.Muted,
        ),
        modifier = modifier
            .heightIn(min = MobileDesign.Control)
            .graphicsLayer { this.alpha = alpha },
    ) {
        Text(text, style = MaterialTheme.typography.bodyMedium, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
    }
}
