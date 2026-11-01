package com.cmuxremote.mobile.adaptive

/**
 * Shared breakpoints for Android and iOS.
 *
 * Priority: ordinary phones first (Compact), then foldable inner displays
 * (TwoPane), then half-open posture (Tabletop).
 */
object PaneLayoutPolicy {
    const val COMPACT_MAX_DP = 600f
    const val DETAIL_MIN_DP = 360f
    const val NARROW_BROWSER_MIN_DP = 240f
    const val NARROW_BROWSER_MAX_DP = 280f
    const val WIDE_BROWSER_MIN_DP = 320f
    const val WIDE_BROWSER_MAX_DP = 400f
    const val WIDE_BREAKPOINT_DP = 720f
    const val SUPPORTING_MIN_TOTAL_DP = 1100f
    const val SUPPORTING_MIN_DETAIL_DP = 480f
    const val SUPPORTING_WIDTH_DP = 360f
    const val TABLETOP_MIN_HEIGHT_DP = 480f
    const val TABLETOP_MIN_GAP_DP = 8f

    fun compute(
        widthDp: Float,
        heightDp: Float,
        hinge: HingeState = HingeState(),
        smallestWidthDp: Float = minOf(widthDp, heightDp),
    ): PaneLayout {
        // A phone in landscape is wide but still a phone. Gate on the shorter
        // side so ordinary phones stay single-column in every orientation;
        // foldable inner displays and tablets pass 600 on both sides.
        if (smallestWidthDp < COMPACT_MAX_DP || widthDp < COMPACT_MAX_DP) {
            return PaneLayout.Compact
        }

        if (hinge.isSeparating && hinge.isHorizontal && hinge.posture == HingePosture.HalfOpened) {
            val gap = hinge.boundsHeightDp.coerceAtLeast(TABLETOP_MIN_GAP_DP)
            val usable = heightDp - gap
            if (usable >= TABLETOP_MIN_HEIGHT_DP) {
                return PaneLayout.Tabletop(
                    topHeightDp = usable / 2f,
                    bottomHeightDp = usable / 2f,
                    gapDp = gap,
                )
            }
        }

        val gap = if (hinge.isSeparating) hinge.boundsWidthDp.coerceAtLeast(0f) else 0f
        var browser = if (widthDp < WIDE_BREAKPOINT_DP) {
            (widthDp * 0.4f).coerceIn(NARROW_BROWSER_MIN_DP, NARROW_BROWSER_MAX_DP)
        } else {
            (widthDp * 0.4f).coerceIn(WIDE_BROWSER_MIN_DP, WIDE_BROWSER_MAX_DP)
        }

        if (hinge.isSeparating && hinge.isVertical && hinge.boundsLeftDp > 0f) {
            browser = hinge.boundsLeftDp.coerceIn(NARROW_BROWSER_MIN_DP, WIDE_BROWSER_MAX_DP)
        }

        var detail = widthDp - browser - gap
        if (detail < DETAIL_MIN_DP) {
            browser = (widthDp - gap - DETAIL_MIN_DP).coerceAtLeast(0f)
            detail = widthDp - browser - gap
        }
        if (detail < DETAIL_MIN_DP) return PaneLayout.Compact

        if (widthDp >= SUPPORTING_MIN_TOTAL_DP) {
            val supporting = SUPPORTING_WIDTH_DP
            val remaining = widthDp - browser - supporting - gap * 2f
            if (remaining >= SUPPORTING_MIN_DETAIL_DP) {
                return PaneLayout.ThreePane(
                    browserWidthDp = browser,
                    detailWidthDp = remaining,
                    supportingWidthDp = supporting,
                    gapDp = gap,
                )
            }
        }

        return PaneLayout.TwoPane(
            browserWidthDp = browser,
            detailWidthDp = detail,
            gapDp = gap,
        )
    }
}
