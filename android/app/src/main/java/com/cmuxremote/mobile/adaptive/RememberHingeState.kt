package com.cmuxremote.mobile.adaptive

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker

@Composable
fun rememberHingeState(): HingeState {
    val context = LocalContext.current
    val density = LocalDensity.current
    val activity = context.findActivity()
    var feature by remember { mutableStateOf<FoldingFeature?>(null) }

    LaunchedEffect(activity) {
        if (activity == null) return@LaunchedEffect
        WindowInfoTracker.getOrCreate(context)
            .windowLayoutInfo(activity)
            .collect { info ->
                feature = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
            }
    }

    return remember(feature, density) {
        val current = feature
        if (current == null) {
            HingeState()
        } else {
            val bounds = current.bounds
            HingeState(
                orientation = when (current.orientation) {
                    FoldingFeature.Orientation.VERTICAL -> HingeOrientation.Vertical
                    FoldingFeature.Orientation.HORIZONTAL -> HingeOrientation.Horizontal
                    else -> HingeOrientation.None
                },
                posture = if (current.state == FoldingFeature.State.HALF_OPENED) {
                    HingePosture.HalfOpened
                } else {
                    HingePosture.Flat
                },
                isSeparating = current.isSeparating,
                boundsLeftDp = with(density) { bounds.left.toDp().value },
                boundsTopDp = with(density) { bounds.top.toDp().value },
                boundsWidthDp = with(density) { bounds.width().toDp().value },
                boundsHeightDp = with(density) { bounds.height().toDp().value },
            )
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
