package com.cmuxremote.mobile.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.BuildConfig
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** The app's own page: which build is running, where it comes from and where it is documented. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MobileDesign.Canvas,
        modifier = Modifier.testTag("about.sheet"),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Cmux Remote", color = MobileDesign.Ink, style = MaterialTheme.typography.titleLarge)
                Text(
                    stringResource(R.string.about_version, "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"),
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.testTag("about.version"),
                )
            }
            AboutLink(R.string.about_website, "https://cmux-remote.trenta.dev", "about.website", context)
            AboutLink(R.string.about_source, "https://github.com/St0neWan9/cmux-remote", "about.source", context)
            Text(stringResource(R.string.about_note), color = MobileDesign.Muted, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun AboutLink(label: Int, url: String, tag: String, context: Context) {
    TextButton(
        onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } },
        modifier = Modifier.testTag(tag),
        contentPadding = PaddingValues(0.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.OpenInNew, contentDescription = null, tint = MobileDesign.Muted)
            Text(stringResource(label), color = MobileDesign.Accent, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
