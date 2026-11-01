package com.cmuxremote.mobile.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Size
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FlashOff
import androidx.compose.material.icons.rounded.FlashOn
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size as GeometrySize
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Full-screen QR capture that reports only the decoded string. The camera belongs to this
 * composable: it is unbound as soon as one code arrives, and the caller validates the value.
 *
 * The frame and tap-to-focus exist because a camera preview alone gives the reader nothing to
 * aim at: an unfocused, unbounded preview looked like the scanner was not running at all.
 */
@Composable
fun QrScannerScreen(
    onScanned: (String) -> Unit,
    onCancel: () -> Unit,
) {
    val context = LocalContext.current
    val currentOnScanned by rememberUpdatedState(onScanned)
    val delivered = remember { AtomicBoolean(false) }
    val hasCamera = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    var unavailable by remember { mutableStateOf(!hasCamera) }
    var permissionGranted by remember { mutableStateOf<Boolean?>(null) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        permissionGranted = granted
        if (!granted) unavailable = true
    }

    LaunchedEffect(Unit) {
        if (!hasCamera) return@LaunchedEffect
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
        permissionGranted = granted
        if (granted) {
            unavailable = false
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    val handleScanned: (String) -> Unit = { value ->
        if (delivered.compareAndSet(false, true)) currentOnScanned(value)
    }

    BackHandler {
        if (!delivered.get()) onCancel()
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (!unavailable && permissionGranted == true) {
            CameraPreview(
                onDetected = handleScanned,
                onUnavailable = { unavailable = true },
            )
        }
        if (unavailable) {
            CameraUnavailable()
        }
        ScannerHeader(
            onCancel = { if (!delivered.get()) onCancel() },
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }
}

/** Keeps the camera preview and the analysis pipeline alive for as long as this screen shows. */
@Composable
private fun CameraPreview(
    onDetected: (String) -> Unit,
    onUnavailable: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            // A TextureView keeps Compose's frame and instructions above the preview on every
            // device; a SurfaceView can punch through them.
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val previewUseCase = remember { Preview.Builder().build() }
    val analysisUseCase = remember {
        ImageAnalysis.Builder()
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(1920, 1080),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                        ),
                    )
                    .build(),
            )
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
    }
    var camera by remember { mutableStateOf<Camera?>(null) }
    var torchOn by remember { mutableStateOf(false) }
    var hasFlash by remember { mutableStateOf(false) }
    var reticle by remember { mutableStateOf<Offset?>(null) }
    var zoomRatio by remember { mutableStateOf(1f) }
    var maxZoom by remember { mutableStateOf(1f) }

    /** Digital zoom helps a code that is readable but too far away for the sensor. */
    fun zoomBy(delta: Float) {
        val current = camera ?: return
        val next = (zoomRatio + delta).coerceIn(1f, maxZoom.coerceAtLeast(1f))
        if (next == zoomRatio) return
        zoomRatio = next
        current.cameraControl.setZoomRatio(next)
    }

    // A tap focuses and meters at that point, and leaves a short-lived frame where it landed.
    val focusAt: (Offset) -> Unit = { point ->
        val current = camera
        if (current != null) {
            val metering = previewView.meteringPointFactory.createPoint(point.x, point.y)
            current.cameraControl.startFocusAndMetering(
                FocusMeteringAction.Builder(
                    metering,
                    FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE,
                )
                    .setAutoCancelDuration(5, TimeUnit.SECONDS)
                    .build(),
            )
            reticle = point
        }
    }
    LaunchedEffect(reticle) {
        if (reticle != null) {
            delay(700)
            reticle = null
        }
    }

    Box(Modifier.fillMaxSize()) {
        AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(camera) {
                    detectTapGestures { focusAt(it) }
                },
        )
        ScanOverlay(reticle = reticle)
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
                .padding(horizontal = 28.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = stringResource(R.string.pair_scan_guide),
                color = Color.White,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
            Text(
                text = stringResource(R.string.pair_scan_focus_hint),
                color = Color.White.copy(alpha = 0.75f),
                style = MaterialTheme.typography.labelMedium,
                textAlign = TextAlign.Center,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Surface(shape = CircleShape, color = Color.Black.copy(alpha = 0.45f)) {
                    TextButton(onClick = { zoomBy(-0.5f) }, enabled = zoomRatio > 1f) {
                        Text("−", color = if (zoomRatio > 1f) Color.White else Color.White.copy(alpha = 0.4f))
                    }
                }
                Text(
                    text = String.format(java.util.Locale.US, "%.1f×", zoomRatio),
                    color = Color.White,
                    style = MaterialTheme.typography.labelMedium,
                )
                Surface(shape = CircleShape, color = Color.Black.copy(alpha = 0.45f)) {
                    TextButton(onClick = { zoomBy(0.5f) }, enabled = zoomRatio < maxZoom) {
                        Text("+", color = if (zoomRatio < maxZoom) Color.White else Color.White.copy(alpha = 0.4f))
                    }
                }
            }
            if (hasFlash) {
                Surface(
                    shape = CircleShape,
                    color = if (torchOn) Color.White else Color.Black.copy(alpha = 0.45f),
                ) {
                    TextButton(
                        onClick = {
                            val next = !torchOn
                            camera?.cameraControl?.enableTorch(next)
                            torchOn = next
                        },
                    ) {
                        Icon(
                            if (torchOn) Icons.Rounded.FlashOn else Icons.Rounded.FlashOff,
                            contentDescription = stringResource(
                                if (torchOn) R.string.pair_scan_torch_off else R.string.pair_scan_torch_on,
                            ),
                            tint = if (torchOn) MobileDesign.Ink else Color.White,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(
                            text = stringResource(R.string.pair_scan_torch),
                            color = if (torchOn) MobileDesign.Ink else Color.White,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
        }
    }

    LaunchedEffect(previewView, lifecycleOwner) {
        var provider: ProcessCameraProvider? = null
        var analyzer: QrCodeAnalyzer? = null
        try {
            provider = awaitCameraProvider(context)
            val currentProvider = provider
            if (currentProvider == null) {
                onUnavailable()
                return@LaunchedEffect
            }
            val currentAnalyzer = QrCodeAnalyzer(ContextCompat.getMainExecutor(context)) { value ->
                currentProvider.unbindAll()
                onDetected(value)
            }
            analyzer = currentAnalyzer
            previewUseCase.setSurfaceProvider(previewView.surfaceProvider)
            analysisUseCase.setAnalyzer(analysisExecutor, currentAnalyzer)
            currentProvider.unbindAll()
            // Ask what the device actually exposes: an emulator or a device without a usable
            // camera used to fall through with a black preview instead of a clear message.
            val selector = when {
                currentProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                currentProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) -> CameraSelector.DEFAULT_FRONT_CAMERA
                else -> {
                    onUnavailable()
                    return@LaunchedEffect
                }
            }
            val bound = try {
                currentProvider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    previewUseCase,
                    analysisUseCase,
                )
            } catch (error: RuntimeException) {
                onUnavailable()
                return@LaunchedEffect
            }
            camera = bound
            hasFlash = bound.cameraInfo.hasFlashUnit()
            maxZoom = bound.cameraInfo.zoomState.value?.maxZoomRatio ?: 1f
            zoomRatio = 1f
            // Focus the middle of the frame once the preview has a size, so the first seconds
            // are not spent on a blurry close-up.
            previewView.post {
                val point = Offset(previewView.width / 2f, previewView.height * 0.42f)
                if (point.x > 0f && point.y > 0f) focusAt(point)
            }
            awaitCancellation()
        } finally {
            camera = null
            torchOn = false
            analysisUseCase.clearAnalyzer()
            analyzer?.close()
            provider?.unbindAll()
            analysisExecutor.shutdown()
        }
    }
}

/** Dims everything outside the code frame and draws its corners; the reticle marks a tap. */
@Composable
private fun ScanOverlay(reticle: Offset?) {
    Canvas(Modifier.fillMaxSize()) {
        val side = minOf(size.width, size.height) * 0.66f
        val left = (size.width - side) / 2f
        val top = (size.height - side) / 2f - size.height * 0.05f
        val frame = Rect(left, top, left + side, top + side)

        val scrim = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(0f, 0f, size.width, size.height))
            addRect(frame)
        }
        drawPath(scrim, Color.Black.copy(alpha = 0.55f))

        val corner = side * 0.16f
        val stroke = 3.dp.toPx()
        val accent = Color.White
        fun bracket(x: Float, y: Float, dx: Float, dy: Float) {
            drawLine(accent, Offset(x, y), Offset(x + dx, y), strokeWidth = stroke)
            drawLine(accent, Offset(x, y), Offset(x, y + dy), strokeWidth = stroke)
        }
        bracket(frame.left, frame.top, corner, corner)
        bracket(frame.right, frame.top, -corner, corner)
        bracket(frame.left, frame.bottom, corner, -corner)
        bracket(frame.right, frame.bottom, -corner, -corner)

        reticle?.let { point ->
            val half = 32.dp.toPx()
            drawRoundRect(
                color = accent,
                topLeft = Offset(point.x - half, point.y - half),
                size = GeometrySize(half * 2, half * 2),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx()),
                style = Stroke(width = 2.dp.toPx()),
            )
        }
    }
}

/** Decoding runs on a worker executor and reports at most one QR payload to the main thread. */
private class QrCodeAnalyzer(
    private val callbackExecutor: Executor,
    private val onValue: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )
    private val consumed = AtomicBoolean(false)

    @Volatile
    private var closed = false

    override fun analyze(image: ImageProxy) {
        if (closed || consumed.get()) {
            image.close()
            return
        }
        val mediaImage = image.image
        if (mediaImage == null) {
            image.close()
            return
        }
        val input = InputImage.fromMediaImage(mediaImage, image.imageInfo.rotationDegrees)
        try {
            scanner.process(input)
                .addOnSuccessListener(callbackExecutor) { barcodes ->
                    if (closed) return@addOnSuccessListener
                    val value = barcodes.asSequence()
                        .mapNotNull { it.rawValue ?: it.displayValue }
                        .firstOrNull()
                    if (value != null && consumed.compareAndSet(false, true)) onValue(value)
                }
                .addOnCompleteListener { image.close() }
        } catch (error: RuntimeException) {
            image.close()
        }
    }

    fun close() {
        closed = true
        scanner.close()
    }
}

/** CameraX publishes its provider asynchronously; await it without stalling the main thread. */
private suspend fun awaitCameraProvider(context: Context): ProcessCameraProvider? =
    suspendCancellableCoroutine<ProcessCameraProvider?> { continuation ->
        val future = runCatching { ProcessCameraProvider.getInstance(context) }.getOrNull()
        if (future == null) {
            if (continuation.isActive) continuation.resume(null)
            return@suspendCancellableCoroutine
        }
        future.addListener(
            {
                if (continuation.isActive) {
                    continuation.resume(runCatching { future.get() }.getOrNull())
                }
            },
            ContextCompat.getMainExecutor(context),
        )
        continuation.invokeOnCancellation { future.cancel(false) }
    }

@Composable
private fun ScannerHeader(
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .padding(horizontal = MobileDesign.PageInset, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            color = Color.White,
            shadowElevation = 6.dp,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 18.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.pair_scan_title),
                    color = MobileDesign.Ink,
                    style = MaterialTheme.typography.titleMedium,
                )
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onCancel) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Accent)
                }
            }
        }
    }
}

@Composable
private fun CameraUnavailable() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MobileDesign.Canvas)
            .padding(MobileDesign.PageInset),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = stringResource(R.string.pair_camera_unavailable),
            color = MobileDesign.Muted,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
    }
}
