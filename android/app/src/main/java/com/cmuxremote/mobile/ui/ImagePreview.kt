package com.cmuxremote.mobile.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.MobileDesign
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A single project image, decoded off the main thread and pannable when zoomed. */
@Composable
fun ImagePreviewScreen(
    title: String,
    bytes: ByteArray?,
    loading: Boolean,
    error: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    onShare: (() -> Unit)? = null,
    onRetry: (() -> Unit)? = null,
) {
    var bitmap by remember(bytes) { mutableStateOf<Bitmap?>(null) }
    var scale by remember(bytes) { mutableStateOf(1f) }
    var offset by remember(bytes) { mutableStateOf(Offset.Zero) }

    LaunchedEffect(bytes) {
        bitmap = if (bytes == null) {
            null
        } else {
            withContext(Dispatchers.Default) {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        }
    }

    Column(modifier.fillMaxSize().background(MobileDesign.Canvas)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier.size(44.dp).clip(CircleShape).clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.ChevronLeft, contentDescription = stringResource(R.string.common_back), tint = MobileDesign.Ink, modifier = Modifier.size(22.dp))
            }
            Text(
                text = title,
                color = MobileDesign.Ink,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (onShare != null && bitmap != null) {
                Text(
                    text = stringResource(R.string.common_share),
                    color = MobileDesign.Accent,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable(onClick = onShare)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val current = bitmap
            when {
                loading -> WorkingIndicator()
                error != null -> Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(horizontal = 24.dp),
                ) {
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    if (onRetry != null) {
                        Text(
                            text = stringResource(R.string.common_retry),
                            color = MobileDesign.Accent,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier
                                .background(MobileDesign.Soft, CircleShape)
                                .clickable(onClick = onRetry)
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                        )
                    }
                }
                current != null -> Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .pointerInput(Unit) {
                            detectTransformGestures { _, pan, zoom, _ ->
                                val next = (scale * zoom).coerceIn(1f, 6f)
                                scale = next
                                offset = if (next <= 1f) Offset.Zero else offset + pan
                            }
                        }
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onDoubleTap = {
                                    if (scale > 1f) {
                                        scale = 1f
                                        offset = Offset.Zero
                                    } else {
                                        scale = 3f
                                    }
                                },
                            )
                        }
                        .clipToBounds()
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                            translationX = offset.x
                            translationY = offset.y
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        bitmap = current.asImageBitmap(),
                        contentDescription = title,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}
