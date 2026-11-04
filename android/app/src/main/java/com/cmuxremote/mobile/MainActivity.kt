package com.cmuxremote.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import com.cmuxremote.mobile.background.PersistentConnectionService
import com.cmuxremote.mobile.ui.CmuxApp
import com.cmuxremote.mobile.ui.theme.CmuxTheme

class MainActivity : ComponentActivity() {
    /** The ongoing connection notification is the service's, but the system asks first. */
    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private val model: CmuxViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (BuildConfig.DEBUG && intent?.getBooleanExtra("force_relay", false) == true) model.forceRelay = true
        // Debug-only test hook: a UI test can hand over the enrollment code the
        // Mac printed, instead of typing a long URL into the field.
        if (BuildConfig.DEBUG) {
            // A UI test can drive identity reset and the "add another Mac" overlay.
            if (intent?.getBooleanExtra("reset_identity", false) == true) model.resetIdentity()
            if (intent?.getBooleanExtra("add_device", false) == true) model.setAddingDevice(true)
            // Typing a URL through an IME is unreliable in a UI test; this seeds one relay.
            intent?.getStringExtra("relay_origin")?.takeIf { it.isNotBlank() }?.let(model::addRelayOrigin)
            // A fixed nearby list keeps a screenshot run off the real network.
            intent?.getStringExtra("nearby_file")?.let { path ->
                runCatching {
                    val rows = org.json.JSONArray(java.io.File(path).readText())
                    (0 until rows.length()).mapNotNull { index ->
                        val row = rows.optJSONObject(index) ?: return@mapNotNull null
                        row.optString("id").takeIf { it.isNotBlank() }?.let { it to row.optString("name") }
                    }
                }.getOrNull()?.takeIf { it.isNotEmpty() }?.let(model::seedDiscovered)
            }
            val direct = intent?.getStringExtra("enroll_code")?.takeIf { it.isNotBlank() }
            // A file survives shell quoting, which the `&` in a code does not.
            val fromFile = intent?.getStringExtra("enroll_file")?.let { path ->
                runCatching { java.io.File(path).readText().trim() }.getOrNull()?.takeIf { it.isNotBlank() }
            }
            (direct ?: fromFile)?.let(model::pair)
        }
        setContent {
            CmuxTheme {
                CmuxApp(model)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Back on screen, the page itself can start the service again on the way out.
        PersistentConnectionService.stop(this)
        model.onForeground()
    }

    override fun onPause() {
        super.onPause()
        // Starting here, while the activity is still visible, is allowed; starting
        // from onStop would hit the Android 12 background-start restriction.
        if (model.shouldKeepAlive()) PersistentConnectionService.start(this)
    }

    override fun onStop() {
        super.onStop()
        model.onBackground(keepAlive = model.shouldKeepAlive())
    }

    override fun onDestroy() {
        if (isFinishing) PersistentConnectionService.stop(this)
        super.onDestroy()
    }
}
