package com.cmuxremote.mobile.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object MobileDesign {
    val Canvas = Color.White
    val Ink = Color(0xFF15171C)
    val Muted = Color(0xFF6D727C)
    val Line = Color(0xFFECEEF2)
    val Soft = Color(0xFFF6F7FA)
    val Accent = Color(0xFF335CF5)
    val AccentSoft = Color(0xFFE8EDFF)
    val Good = Color(0xFF2F9E6B)
    /** An outcome-unknown write: not a failure, yet not confirmed either. */
    val Warning = Color(0xFFC77700)
    val Code = Color(0xFFF1F3F7)
    /** The iPhone tool card's very light content surface. */
    val ToolCard = Color(0xFFF9F9F9)

    val PageInset = 20.dp
    val SectionGap = 24.dp
    val RowGap = 12.dp
    val CardRadius = 22.dp
    /** The soft 6% black the iPhone gives every floating surface. */
    val Shadow = androidx.compose.ui.graphics.Color(0x0F000000)
    val Control = 44.dp
}
