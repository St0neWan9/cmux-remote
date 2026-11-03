package com.cmuxremote.mobile.adaptive

/**
 * The only layout decision either platform makes. Widths are in dp (Android)
 * or pt (iOS); both use the same breakpoints and pane minimums.
 */
sealed interface PaneLayout {
    data object Compact : PaneLayout

    data class TwoPane(
        val browserWidthDp: Float,
        val detailWidthDp: Float,
        val gapDp: Float,
    ) : PaneLayout

    data class ThreePane(
        val browserWidthDp: Float,
        val detailWidthDp: Float,
        val supportingWidthDp: Float,
        val gapDp: Float,
    ) : PaneLayout

    data class Tabletop(
        val topHeightDp: Float,
        val bottomHeightDp: Float,
        val gapDp: Float,
    ) : PaneLayout
}
