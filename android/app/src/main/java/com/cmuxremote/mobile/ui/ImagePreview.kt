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
import androidx.compose.ui.layout.onSizeChanged
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
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var offset by remember(bytes) { mutableStateOf(Offset.Zero) }
    var boxSize by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    fun clamped(value: Offset, scale: Float): Offset {
        val maxX = ((scale - 1f) * boxSize.width / 2f).coerceAtLeast(0f)
        val maxY = ((scale - 1f) * boxSize.height / 2f).coerceAtLeast(0f)
        return Offset(value.x.coerceIn(-maxX, maxX), value.y.coerceIn(-maxY, maxY))
    }

    LaunchedEffect(bytes) {
        bitmap = if (bytes == null) {
            null
        } else {
            withContext(Dispatchers.Default) {
                // The Bridge records a single JPEG frame; anything else is not shown.
                if (!isJpeg(bytes)) return@withContext null
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth !in 1..1600 || bounds.outHeight !in 1..1600) {
                    null
                } else {
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
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
            if (bytes != null && bitmap != null) {
                var copied by remember { mutableStateOf(false) }
                val context = androidx.compose.ui.platform.LocalContext.current
                Text(
                    text = stringResource(if (copied) R.string.common_copied else R.string.common_copy),
                    color = MobileDesign.Accent,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.clickable {
                        copied = copyImage(context, bytes)
                    }.padding(vertical = 4.dp),
                )
            }
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
                        .onSizeChanged { boxSize = it }
                        .pointerInput(Unit) {
                            detectTransformGestures { _, pan, zoom, _ ->
                                val next = (scale * zoom).coerceIn(1f, 6f)
                                scale = next
                                offset = if (next <= 1f) Offset.Zero else clamped(offset + pan, next)
                            }
                        }
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onDoubleTap = {
                                    if (scale > 1f) {
                                        scale = 1f
                                        offset = Offset.Zero
                                    } else {
                                        scale = 2.5f
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


/** Copies a JPEG to the clipboard as a content URI the system can paste. */
private fun copyImage(context: android.content.Context, bytes: ByteArray): Boolean = runCatching {
    val directory = java.io.File(context.cacheDir, "clipboard").apply { mkdirs() }
    val file = java.io.File(directory, "image-${java.util.UUID.randomUUID()}.jpg")
    file.writeBytes(bytes)
    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val clipboard = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
    clipboard.setPrimaryClip(android.content.ClipData.newUri(context.contentResolver, "image", uri))
    true
}.getOrDefault(false)

/** A recorded image is a single JPEG frame, as the iPhone's image source check requires. */
private fun isJpeg(bytes: ByteArray): Boolean =
    bytes.size > 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()
