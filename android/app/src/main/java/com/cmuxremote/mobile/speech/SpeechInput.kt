package com.cmuxremote.mobile.speech

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * On-device dictation only; no network recognizer, no audio leaves the device.
 *
 * Mirrors `SpeechInputService` / `SpeechDraftModel` on iOS: a session either produces
 * recognized text, is stopped by the caller, or fails with one of the stable codes in
 * [State.error]. [start] suspends until the session ends (final result, timeout,
 * [finish], [cancel], or a failure) and returns the terminal snapshot. [finish] lets
 * the composer take the current transcript immediately. Recognized text is never
 * logged.
 */
class SpeechInput(private val context: Context) {

    data class State(
        val availability: Availability,
        val listening: Boolean = false,
        val partial: String = "",
        /** Stable code: "speech_unavailable" | "speech_denied" | "speech_no_speech" | "speech_too_long". */
        val error: String? = null,
    )

    enum class Availability { Ready, Unavailable, PermissionDenied }

    /** Matches the iOS deadline: one dictation session may run for at most 60 s. */
    val maxDurationSeconds: Int = 60

    /** Matches the iOS bound: the recognized draft may not exceed 8192 UTF-8 bytes. */
    val maxBytes: Int = 8192

    private val mainHandler = Handler(Looper.getMainLooper())
    /** Receives the live transcript while dictation runs, for the draft strip. */
    var onPartial: ((String) -> Unit)? = null
    private var session: Session? = null
    private var permissionRequest: kotlinx.coroutines.CancellableContinuation<Boolean>? = null
    @Volatile private var partial: String = ""

    /** Read-only preflight; reports what [start] would do without requesting anything. */
    fun availability(): Availability {
        if (!onDeviceRecognitionAvailable()) return Availability.Unavailable
        return if (hasRecordPermission()) Availability.Ready else Availability.PermissionDenied
    }

    /**
     * Requests RECORD_AUDIO when needed, starts on-device recognition, and suspends
     * until the session ends. Any failed preflight fails closed: the command recognizer
     * (which may use the network) is never created.
     */
    @SuppressLint("MissingPermission")
    suspend fun start(): State = withContext(Dispatchers.Main.immediate) {
        closeSession()
        partial = ""
        if (!onDeviceRecognitionAvailable()) {
            return@withContext State(Availability.Unavailable, error = ERROR_UNAVAILABLE)
        }
        if (!hasRecordPermission() && !requestRecordPermission()) {
            return@withContext State(Availability.PermissionDenied, error = ERROR_DENIED)
        }
        val recognizer = createOnDeviceRecognizer()
            ?: return@withContext State(Availability.Unavailable, error = ERROR_UNAVAILABLE)
        val intent = recognitionIntent()
        val supported = try {
            supportsOnDeviceRecognition(recognizer, intent)
        } catch (cancelled: CancellationException) {
            runCatching { recognizer.destroy() }
            throw cancelled
        }
        if (!supported) {
            runCatching { recognizer.destroy() }
            return@withContext State(Availability.Unavailable, error = ERROR_UNAVAILABLE)
        }
        val current = Session(recognizer)
        session = current
        try {
            recognizer.setRecognitionListener(current)
            recognizer.startListening(intent)
        } catch (_: Throwable) {
            current.abort()
            return@withContext State(Availability.Unavailable, error = ERROR_UNAVAILABLE)
        }
        try {
            withTimeoutOrNull(maxDurationSeconds * 1_000L) { current.result.await() }
                ?: run {
                    // The deadline stops the microphone; the last accepted partial is retained.
                    current.complete(ERROR_TOO_LONG)
                    State(Availability.Ready, listening = false, partial = partial, error = ERROR_TOO_LONG)
                }
        } catch (cancelled: CancellationException) {
            current.abort()
            throw cancelled
        }
    }

    /** Stops listening and returns the transcript captured so far, trimmed. */
    fun finish(): String {
        val text = partial.trim()
        runOnMain { finishOnMain(text) }
        return text
    }

    /** Aborts the session and clears its transcript; a suspended [start] throws. */
    fun cancel() {
        runOnMain {
            permissionRequest?.cancel()
            permissionRequest = null
            closeSession()
        }
    }

    private fun finishOnMain(text: String) {
        val current = session ?: return
        if (current.isClosed) return
        partial = text
        current.complete(if (text.isBlank()) ERROR_NO_SPEECH else null)
    }

    private fun closeSession() {
        partial = ""
        val current = session ?: return
        session = null
        current.abort()
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun hasRecordPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /**
     * Requests the microphone permission through the host activity's result registry.
     * Fails closed when there is no activity to ask, when the request cannot be
     * registered, or when the user has not answered within a bounded window.
     */
    private suspend fun requestRecordPermission(): Boolean {
        val activity = findActivity(context) as? ComponentActivity ?: return false
        val registry = activity.activityResultRegistry
        return withTimeoutOrNull(PERMISSION_TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                val key = "cmux-remote.speech.record.${UUID.randomUUID()}"
                var launcher: ActivityResultLauncher<String>? = null
                val registered = runCatching {
                    registry.register(key, ActivityResultContracts.RequestPermission()) { granted ->
                        launcher?.unregister()
                        permissionRequest = null
                        if (continuation.isActive) continuation.resume(granted)
                    }
                }
                if (registered.isFailure) {
                    if (continuation.isActive) continuation.resume(false)
                    return@suspendCancellableCoroutine
                }
                launcher = registered.getOrThrow()
                permissionRequest = continuation
                continuation.invokeOnCancellation {
                    permissionRequest = null
                    mainHandler.post { runCatching { launcher?.unregister() } }
                }
                launcher.launch(Manifest.permission.RECORD_AUDIO)
            }
        } ?: false
    }

    private tailrec fun findActivity(current: Context): Activity? = when (current) {
        is Activity -> current
        is ContextWrapper -> findActivity(current.baseContext)
        else -> null
    }

    private fun onDeviceRecognitionAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isOnDeviceRecognitionAvailable()

    @RequiresApi(Build.VERSION_CODES.S)
    private fun isOnDeviceRecognitionAvailable(): Boolean =
        SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    @RequiresApi(Build.VERSION_CODES.S)
    private fun createOnDeviceRecognizerNow(): SpeechRecognizer? =
        runCatching { SpeechRecognizer.createOnDeviceSpeechRecognizer(context) }.getOrNull()

    private fun createOnDeviceRecognizer(): SpeechRecognizer? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) createOnDeviceRecognizerNow() else null

    private fun recognitionIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        }

    /**
     * On API 33+ `RecognitionSupport` must confirm that the requested language is
     * handled by an on-device model. On API 31/32 only `isOnDeviceRecognitionAvailable`
     * exists and the recognizer was created with `createOnDeviceSpeechRecognizer`.
     */
    private suspend fun supportsOnDeviceRecognition(
        recognizer: SpeechRecognizer,
        intent: Intent,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkRecognitionSupport(recognizer, intent)
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private suspend fun checkRecognitionSupport(
        recognizer: SpeechRecognizer,
        intent: Intent,
    ): Boolean {
        val languageTag = intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE)
            ?: Locale.getDefault().toLanguageTag()
        val executor = Executor { command -> mainHandler.post(command) }
        return withTimeoutOrNull(SUPPORT_TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                val callback = object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        if (continuation.isActive) {
                            continuation.resume(support.listsLanguage(languageTag))
                        }
                    }

                    override fun onError(error: Int) {
                        if (continuation.isActive) continuation.resume(false)
                    }
                }
                val failed = runCatching {
                    recognizer.checkRecognitionSupport(intent, executor, callback)
                }.isFailure
                if (failed && continuation.isActive) continuation.resume(false)
            }
        } ?: false
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun RecognitionSupport.listsLanguage(languageTag: String): Boolean {
        val languages = installedOnDeviceLanguages +
            pendingOnDeviceLanguages +
            supportedOnDeviceLanguages
        if (languages.isEmpty()) return true
        val wanted = Locale.forLanguageTag(languageTag)
        return languages.any { candidate ->
            candidate.equals(languageTag, ignoreCase = true) ||
                Locale.forLanguageTag(candidate).language.equals(wanted.language, ignoreCase = true)
        }
    }

    private fun utf8Length(text: String): Int = text.toByteArray(Charsets.UTF_8).size

    @Suppress("DEPRECATION")
    private fun Bundle.firstText(): String? =
        getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

    /**
     * One live recognizer. It is itself the [RecognitionListener]; all callbacks and
     * completion run on the main thread. Once closed it ignores late native results.
     */
    private inner class Session(private val recognizer: SpeechRecognizer) : RecognitionListener {
        val result = CompletableDeferred<State>()
        var isClosed: Boolean = false
            private set

        fun complete(error: String?) {
            if (isClosed) return
            isClosed = true
            if (session === this) session = null
            runCatching { recognizer.stopListening() }
            mainHandler.post { runCatching { recognizer.destroy() } }
            val availability = when (error) {
                ERROR_DENIED -> Availability.PermissionDenied
                ERROR_UNAVAILABLE -> Availability.Unavailable
                else -> Availability.Ready
            }
            result.complete(
                State(availability = availability, listening = false, partial = partial, error = error),
            )
        }

        fun abort() {
            if (isClosed) return
            isClosed = true
            if (session === this) session = null
            runCatching { recognizer.cancel() }
            mainHandler.post { runCatching { recognizer.destroy() } }
            if (!result.isCompleted) result.cancel()
        }

        private fun accept(text: String, final: Boolean) {
            if (utf8Length(text) > maxBytes) {
                complete(ERROR_TOO_LONG)
                return
            }
            partial = text
            if (final) {
                complete(if (text.isBlank()) ERROR_NO_SPEECH else null)
            } else {
                runOnMain { onPartial?.invoke(text) }
            }
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit

        override fun onBeginningOfSpeech() = Unit

        override fun onRmsChanged(rmsdB: Float) = Unit

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() = Unit

        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onError(error: Int) {
            if (isClosed) return
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                -> complete(if (partial.isBlank()) ERROR_NO_SPEECH else null)

                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> complete(ERROR_DENIED)

                // ERRORS from the service (including a network-only recognizer) are not
                // retried against the network; the session simply becomes unavailable.
                else -> complete(ERROR_UNAVAILABLE)
            }
        }

        override fun onResults(results: Bundle?) {
            if (isClosed) return
            accept(results?.firstText() ?: "", final = true)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            if (isClosed) return
            accept(partialResults?.firstText() ?: return, final = false)
        }
    }

    companion object {
        /** On-device recognition or its language model is not available on this device. */
        const val ERROR_UNAVAILABLE = "speech_unavailable"

        /** RECORD_AUDIO was refused, or the recognizer lost the permission. */
        const val ERROR_DENIED = "speech_denied"

        /** The session ended without any recognized speech. */
        const val ERROR_NO_SPEECH = "speech_no_speech"

        /** The 60 s deadline elapsed or the transcript passed 8192 UTF-8 bytes. */
        const val ERROR_TOO_LONG = "speech_too_long"

        private const val PERMISSION_TIMEOUT_MILLIS = 60_000L
        private const val SUPPORT_TIMEOUT_MILLIS = 5_000L
    }
}
