package com.cmuxremote.mobile.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaneLayoutPolicyTest {
    @Test
    fun normalPhoneIsCompact() {
        assertEquals(PaneLayout.Compact, PaneLayoutPolicy.compute(393f, 852f))
    }

    @Test
    fun normalPhoneLandscapeStaysCompact() {
        assertEquals(PaneLayout.Compact, PaneLayoutPolicy.compute(914f, 411f))
    }

    @Test
    fun foldableInnerPortraitUsesTwoPane() {
        val layout = PaneLayoutPolicy.compute(673f, 841f) as PaneLayout.TwoPane
        assertEquals(269.2f, layout.browserWidthDp, 0.01f)
        assertEquals(403.8f, layout.detailWidthDp, 0.01f)
    }

    @Test
    fun narrowSplitViewIsCompact() {
        assertEquals(PaneLayout.Compact, PaneLayoutPolicy.compute(469f, 890f))
    }

    @Test
    fun sixHundredStartsTwoPane() {
        val layout = PaneLayoutPolicy.compute(600f, 890f) as PaneLayout.TwoPane
        assertEquals(240f, layout.browserWidthDp, 0.01f)
        assertEquals(360f, layout.detailWidthDp, 0.01f)
    }

    @Test
    fun xiaomiInnerPortraitUsesCompactBrowser() {
        val layout = PaneLayoutPolicy.compute(700f, 890f) as PaneLayout.TwoPane
        assertEquals(280f, layout.browserWidthDp, 0.01f)
        assertEquals(420f, layout.detailWidthDp, 0.01f)
    }

    @Test
    fun sevenHundredTwentyUsesWideBrowser() {
        val layout = PaneLayoutPolicy.compute(720f, 890f) as PaneLayout.TwoPane
        assertEquals(320f, layout.browserWidthDp, 0.01f)
        assertEquals(400f, layout.detailWidthDp, 0.01f)
    }

    @Test
    fun landscapeInnerUsesWideBrowser() {
        val layout = PaneLayoutPolicy.compute(890f, 626f) as PaneLayout.TwoPane
        assertEquals(356f, layout.browserWidthDp, 0.01f)
        assertEquals(534f, layout.detailWidthDp, 0.01f)
    }

    @Test
    fun supportingPaneNeedsEnoughDetailWidth() {
        val layout = PaneLayoutPolicy.compute(1240f, 890f)
        assertTrue(layout is PaneLayout.ThreePane)
        val three = layout as PaneLayout.ThreePane
        assertEquals(400f, three.browserWidthDp, 0.01f)
        assertEquals(480f, three.detailWidthDp, 0.01f)
        assertEquals(360f, three.supportingWidthDp, 0.01f)
    }

    @Test
    fun verticalHingeSnapsDividerAndKeepsDetailMinimum() {
        val hinge = HingeState(
            orientation = HingeOrientation.Vertical,
            posture = HingePosture.HalfOpened,
            isSeparating = true,
            boundsLeftDp = 340f,
            boundsWidthDp = 20f,
        )
        val layout = PaneLayoutPolicy.compute(700f, 890f, hinge) as PaneLayout.TwoPane
        assertEquals(320f, layout.browserWidthDp, 0.01f)
        assertEquals(360f, layout.detailWidthDp, 0.01f)
        assertEquals(20f, layout.gapDp, 0.01f)
    }

    @Test
    fun horizontalHalfOpenBecomesTabletop() {
        val hinge = HingeState(
            orientation = HingeOrientation.Horizontal,
            posture = HingePosture.HalfOpened,
            isSeparating = true,
            boundsHeightDp = 10f,
        )
        val layout = PaneLayoutPolicy.compute(890f, 626f, hinge) as PaneLayout.Tabletop
        assertEquals(308f, layout.topHeightDp, 0.01f)
        assertEquals(308f, layout.bottomHeightDp, 0.01f)
        assertEquals(10f, layout.gapDp, 0.01f)
    }

    @Test
    fun flatHingeDoesNotChangeWidthLayout() {
        val hinge = HingeState(orientation = HingeOrientation.Vertical, isSeparating = false)
        val layout = PaneLayoutPolicy.compute(700f, 890f, hinge) as PaneLayout.TwoPane
        assertEquals(280f, layout.browserWidthDp, 0.01f)
        assertEquals(420f, layout.detailWidthDp, 0.01f)
    }
}
