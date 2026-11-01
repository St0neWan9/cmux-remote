package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.ui.theme.MobileDesign

@Composable
fun WorkingIndicator(size: Dp = 14.dp) {
    CircularProgressIndicator(
        modifier = Modifier.size(size),
        color = MobileDesign.Accent,
        strokeWidth = 2.dp,
    )
}
