package com.cmuxremote.mobile.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

/**
 * The running-turn spinner: a quiet gray arc rotating once per 0.9 s, as on the
 * iPhone, with a label for a screen reader.
 */
@Composable
fun WorkingIndicator(size: Dp = 16.dp, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.common_working)
    val transition = rememberInfiniteTransition(label = "working")
    val angle by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "working-angle",
    )
    Canvas(
        modifier = Modifier
            .size(size)
            .rotate(angle)
            .testTag("chat.working")
            .semantics { contentDescription = label }
            .then(modifier),
    ) {
        drawArc(
            color = MobileDesign.Muted,
            startAngle = 0f,
            sweepAngle = 280f,
            useCenter = false,
            style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}
