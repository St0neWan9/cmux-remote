package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

@Composable
fun TopBar(
    title: String,
    modifier: Modifier = Modifier,
    onMenu: (() -> Unit)? = null,
    onBack: (() -> Unit)? = null,
    onSearch: () -> Unit = {},
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        when {
            onBack != null -> IconButton(onClick = onBack) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink)
            }
            onMenu != null -> IconButton(onClick = onMenu) {
                Icon(Icons.Rounded.Menu, contentDescription = stringResource(R.string.common_menu), tint = MobileDesign.Ink)
            }
        }
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = title,
                color = MobileDesign.Ink,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Icon(
                Icons.Rounded.KeyboardArrowDown,
                contentDescription = null,
                tint = MobileDesign.Muted,
                modifier = Modifier.size(18.dp),
            )
        }
        if (trailing != null) {
            trailing()
        } else {
            IconButton(onClick = onSearch) {
                Icon(Icons.Rounded.Search, contentDescription = stringResource(R.string.common_search), tint = MobileDesign.Ink)
            }
        }
    }
}

@Composable
fun TopBarIcon(icon: ImageVector, contentDescription: String, onClick: () -> Unit = {}) {
    IconButton(onClick = onClick) {
        Icon(icon, contentDescription = contentDescription, tint = MobileDesign.Ink)
    }
}
