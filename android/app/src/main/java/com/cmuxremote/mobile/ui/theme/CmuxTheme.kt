package com.cmuxremote.mobile.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val CmuxColors = lightColorScheme(
    primary = MobileDesign.Accent,
    onPrimary = Color.White,
    background = MobileDesign.Canvas,
    onBackground = MobileDesign.Ink,
    surface = MobileDesign.Canvas,
    onSurface = MobileDesign.Ink,
    surfaceVariant = MobileDesign.Soft,
    onSurfaceVariant = MobileDesign.Muted,
    outline = MobileDesign.Line,
)

private val CmuxTypography = Typography(
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 17.sp,
        lineHeight = 23.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        // The iPhone's .body is 17 pt; sp keeps the reader's font scale.
        fontSize = 17.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
)

@Composable
fun CmuxTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = CmuxColors,
        typography = CmuxTypography,
        content = content,
    )
}
