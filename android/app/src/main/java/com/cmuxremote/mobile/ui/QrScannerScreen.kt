package com.cmuxremote.mobile.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
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
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Full-screen QR capture that reports only the decoded string. The camera belongs to this
 * composable: it is unbound as soon as one code arrives, and the caller validates the value.
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
        PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
    }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val previewUseCase = remember { Preview.Builder().build() }
    val analysisUseCase = remember {
        ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
    }

    AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())

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
            try {
                currentProvider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    previewUseCase,
                    analysisUseCase,
                )
            } catch (backCameraError: RuntimeException) {
                // A device may expose only a front-facing camera.
                currentProvider.unbindAll()
                try {
                    currentProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_FRONT_CAMERA,
                        previewUseCase,
                        analysisUseCase,
                    )
                } catch (frontCameraError: RuntimeException) {
                    onUnavailable()
                    return@LaunchedEffect
                }
            }
            awaitCancellation()
        } finally {
            analysisUseCase.clearAnalyzer()
            analyzer?.close()
            provider?.unbindAll()
            analysisExecutor.shutdown()
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
