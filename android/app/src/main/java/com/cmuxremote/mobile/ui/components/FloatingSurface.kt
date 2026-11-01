package com.cmuxremote.mobile.ui.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.ui.theme.MobileDesign

@Composable
fun FloatingSurface(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(16.dp),
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(MobileDesign.CardRadius)
    Surface(
        // iOS cards span the page; a card sized by its text broke that layout
        // on Add Device, Start Session and the list's reminders.
        modifier = modifier
            .fillMaxWidth()
            .shadow(6.dp, shape, clip = false)
            .border(0.5.dp, MobileDesign.Line, shape),
        shape = shape,
        color = MobileDesign.Canvas,
    ) {
        Column(Modifier.padding(contentPadding), content = content)
    }
}
