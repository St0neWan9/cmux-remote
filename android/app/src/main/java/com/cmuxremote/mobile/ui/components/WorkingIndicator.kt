package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** The running-turn spinner; its label is what a screen reader announces. */
@Composable
fun WorkingIndicator(size: Dp = 14.dp) {
    val label = stringResource(R.string.common_working)
    CircularProgressIndicator(
        modifier = Modifier
            .size(size)
            .semantics { contentDescription = label },
        color = MobileDesign.Accent,
        strokeWidth = 2.dp,
    )
}
