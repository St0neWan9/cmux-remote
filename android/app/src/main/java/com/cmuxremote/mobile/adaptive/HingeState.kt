package com.cmuxremote.mobile.adaptive

/**
 * The window's fold posture, reduced to the facts the layout policy needs.
 * Android maps FoldingFeature into this; iOS maps onHingeChange/reservedRegions.
 */
data class HingeState(
    val orientation: HingeOrientation = HingeOrientation.None,
    val posture: HingePosture = HingePosture.Flat,
    val isSeparating: Boolean = false,
    val boundsLeftDp: Float = 0f,
    val boundsTopDp: Float = 0f,
    val boundsWidthDp: Float = 0f,
    val boundsHeightDp: Float = 0f,
) {
    val isVertical: Boolean get() = orientation == HingeOrientation.Vertical
    val isHorizontal: Boolean get() = orientation == HingeOrientation.Horizontal
}

enum class HingeOrientation { None, Vertical, Horizontal }

enum class HingePosture { Flat, HalfOpened }
