package com.cmuxremote.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.activity.enableEdgeToEdge
import com.cmuxremote.mobile.ui.CmuxApp
import com.cmuxremote.mobile.ui.theme.CmuxTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val model: CmuxViewModel by viewModels()
        if (BuildConfig.DEBUG && intent?.getBooleanExtra("force_relay", false) == true) model.forceRelay = true
        // Debug-only test hook: a UI test can hand over the enrollment code the
        // Mac printed, instead of typing a long URL into the field.
        if (BuildConfig.DEBUG) {
            // A UI test can drive the "add another Mac" overlay, not only first use.
            if (intent?.getBooleanExtra("add_device", false) == true) model.setAddingDevice(true)
            // Typing a URL through an IME is unreliable in a UI test; this seeds one relay.
            intent?.getStringExtra("relay_origin")?.takeIf { it.isNotBlank() }?.let(model::addRelayOrigin)
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
}
