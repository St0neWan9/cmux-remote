package com.cmuxremote.mobile.ui

import android.content.Context
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign
import kotlin.math.abs
import kotlinx.coroutines.launch

/** The panel corner radius the page takes on while the drawer is exposed. */
private val PanelCornerRadius = 38.dp

/** The width of the leading strip that can pull the drawer open. */
private val EdgeStripWidth = 12.dp

/**
 * Spring response and damping match the iOS drawer; Compose takes stiffness in mass-normalized
 * units, so the response time is converted with stiffness = (2π / response)².
 */
private const val SettleResponseSeconds = 0.32f
private const val SettleDampingRatio = 0.9f
private val SettleStiffness: Float =
    ((2.0 * Math.PI / SettleResponseSeconds) * (2.0 * Math.PI / SettleResponseSeconds)).toFloat()

/** How far a release is projected forward from its velocity before deciding the target. */
private const val ProjectedVelocitySeconds = 0.3f

/** The iOS gesture's 25% threshold for committing to the other side. */
private const val CommitFraction = 0.25f

/**
 * Left drawer over the page: the page slides right with a rounded panel and shadow,
 * a scrim closes it, an edge strip opens it, and a drag follows the finger.
 */
@Composable
fun AppDrawer(
    open: Boolean,
    onOpenChange: (Boolean) -> Unit,
    allowsEdgeOpening: Boolean = true,
    drawer: @Composable (close: () -> Unit) -> Unit,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val closeSidebarLabel = stringResource(R.string.common_close_sidebar)
    val reduceMotion = remember(context) { systemAnimationsDisabled(context) }

    // Back closes the drawer before it reaches the host's back handling.
    BackHandler(enabled = open) { onOpenChange(false) }

    BoxWithConstraints(Modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        val widthDp = minOf(440.dp, maxWidth * 0.77f)
        val widthPx = with(LocalDensity.current) { widthDp.toPx() }

        // A resize rebuilds the displacement from the presentation binding, cancelling a drag.
        val offset = remember(widthPx) { Animatable(if (open) widthPx else 0f) }
        // A drag writes these directly; the Animatable only settles after release.
        val dragOffset = remember { mutableFloatStateOf(0f) }
        val dragging = remember { mutableStateOf(false) }
        val raised by remember(offset) { derivedStateOf { offset.value > 0f } }

        val cornerRadius = if (raised) PanelCornerRadius else 0.dp
        val shape = RoundedCornerShape(cornerRadius)
        val settle = settleSpec(reduceMotion)

        // Presentation changes (back, scrim, close callback, edge opening disabled) settle the
        // displacement. A drag only snapTo's the value, so this effect does not fight it until
        // the presentation actually changes.
        LaunchedEffect(open, widthPx, allowsEdgeOpening, reduceMotion) {
            offset.animateTo(if (open) widthPx else 0f, settle)
        }

        val close: () -> Unit = { onOpenChange(false) }
        val scrimInteraction = remember { MutableInteractionSource() }

        // A closing drag starts from the exposed width; an opening drag starts from zero.
        val closingDrag = if (open) {
            Modifier.drawerDrag(
                widthPx = widthPx,
                offset = offset,
                dragOffset = dragOffset,
                dragging = dragging,
                opening = false,
                open = open,
                reduceMotion = reduceMotion,
                onOpenChange = onOpenChange,
            )
        } else {
            Modifier
        }
        val openingDrag = if (!open && allowsEdgeOpening) {
            Modifier.drawerDrag(
                widthPx = widthPx,
                offset = offset,
                dragOffset = dragOffset,
                dragging = dragging,
                opening = true,
                open = open,
                reduceMotion = reduceMotion,
                onOpenChange = onOpenChange,
            )
        } else {
            Modifier
        }

        // The drawer sits behind the page. While closed it is fully transparent, blocked from
        // hit testing, and removed from semantics; while open a horizontal drag on it closes.
        Box(
            modifier = Modifier
                .width(widthDp)
                .fillMaxHeight()
                .alpha(if (raised) 1f else 0f)
                .then(if (open) Modifier else Modifier.blockPointerInputs())
                .then(closingDrag)
                .then(if (open) Modifier else Modifier.clearAndSetSemantics { }),
        ) {
            drawer(close)
        }

        // The page is drawn full size, translated by the displacement, and clipped to the panel
        // radius while any part of the drawer is exposed. The shadow follows the same transition.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { translationX = if (dragging.value) dragOffset.floatValue else offset.value }
                .shadow(
                    elevation = if (raised) 16.dp else 0.dp,
                    shape = shape,
                    clip = false,
                    ambientColor = Color.Black.copy(alpha = 0.13f),
                    spotColor = Color.Black.copy(alpha = 0.13f),
                )
                .background(MobileDesign.Canvas, shape)
                .clip(shape),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .then(if (open) Modifier.clearAndSetSemantics { } else Modifier),
            ) {
                content()
            }

            if (open) {
                // White 40% scrim over the page; taps and left drags close the drawer.
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.White.copy(alpha = 0.4f))
                        .semantics { contentDescription = closeSidebarLabel }
                        .clickable(
                            interactionSource = scrimInteraction,
                            indication = null,
                            role = Role.Button,
                            onClickLabel = closeSidebarLabel,
                            onClick = close,
                        )
                        .then(closingDrag),
                )
            }
        }

        // The narrow leading strip only exists while closed; it pulls the drawer open.
        if (!open && allowsEdgeOpening) {
            Box(
                modifier = Modifier
                    .width(EdgeStripWidth)
                    .fillMaxHeight()
                    .clearAndSetSemantics { }
                    .then(openingDrag),
            )
        }
    }
}

/**
 * A horizontal drag that moves the drawer with the finger and settles on release.
 *
 * The gesture only claims the pointer after [EdgeStripWidth] or the platform touch slop (which
 * ever is larger) and only when horizontal movement dominates, so vertical scrolling still works.
 * On release the translation is projected forward with the tracked velocity before committing,
 * mirroring the iOS `DrawerDragState`.
 */
@Composable
private fun Modifier.drawerDrag(
    widthPx: Float,
    offset: Animatable<Float, AnimationVector1D>,
    dragOffset: androidx.compose.runtime.MutableFloatState,
    dragging: androidx.compose.runtime.MutableState<Boolean>,
    opening: Boolean,
    open: Boolean,
    reduceMotion: Boolean,
    onOpenChange: (Boolean) -> Unit,
): Modifier {
    val latestOpen = rememberUpdatedState(open)
    val latestOnOpenChange = rememberUpdatedState(onOpenChange)
    val scope = rememberCoroutineScope()
    val settle = settleSpec(reduceMotion)

    return pointerInput(widthPx, opening, reduceMotion) {
        if (widthPx <= 0f) return@pointerInput
        val minimumDistance = maxOf(EdgeStripWidth.toPx(), viewConfiguration.touchSlop)
        val tracker = VelocityTracker()

        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            tracker.resetTracking()
            tracker.addPosition(down.uptimeMillis, down.position)

            var totalX = 0f
            var totalY = 0f
            var started = false
            var released = false

            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                tracker.addPosition(change.uptimeMillis, change.position)

                val delta = change.positionChange()
                totalX += delta.x
                totalY += delta.y

                if (!started) {
                    if (abs(totalX) >= minimumDistance && abs(totalX) > abs(totalY)) {
                        started = true
                    } else if (abs(totalY) >= minimumDistance) {
                        // The pointer belongs to a vertical scroll, not the drawer.
                        break
                    }
                }

                if (started) {
                    val base = if (opening) 0f else widthPx
                    dragging.value = true
                    dragOffset.floatValue = (base + totalX).coerceIn(0f, widthPx)
                    change.consume()
                }

                if (change.changedToUpIgnoreConsumed()) {
                    released = true
                    break
                }
            }

            if (!started) return@awaitEachGesture
            val releasedAt = dragOffset.floatValue
            dragging.value = false
            scope.launch { offset.snapTo(releasedAt) }

            val current = latestOpen.value
            val target = if (!released) {
                // A cancelled stream leaves the drawer where the presentation says it belongs.
                current
            } else {
                val horizontal = abs(totalX) > abs(totalY)
                val predicted = totalX + tracker.calculateVelocity().x * ProjectedVelocitySeconds
                when {
                    !horizontal -> current
                    abs(totalX) <= 0f -> current
                    opening -> predicted > widthPx * CommitFraction
                    else -> predicted >= -widthPx * CommitFraction
                }
            }

            latestOnOpenChange.value(target)
            if (target == current) {
                // The presentation binding does not change, so this gesture owns the rebound.
                scope.launch { offset.animateTo(if (target) widthPx else 0f, settle) }
            }
        }
    }
}

/** Consumes pointer input on its subtree so a closed drawer can never be touched. */
private fun Modifier.blockPointerInputs(): Modifier = pointerInput(Unit) {
    awaitPointerEventScope {
        while (true) {
            awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
        }
    }
}

/** The settle animation: a snap when the platform has disabled animator duration. */
private fun settleSpec(reduceMotion: Boolean): AnimationSpec<Float> =
    if (reduceMotion) {
        snap()
    } else {
        spring(dampingRatio = SettleDampingRatio, stiffness = SettleStiffness)
    }

/** Reads Android's animator duration scale; zero means the user disabled system animations. */
private fun systemAnimationsDisabled(context: Context): Boolean = runCatching {
    Settings.Global.getFloat(
        context.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f,
    ) == 0f
}.getOrDefault(false)
