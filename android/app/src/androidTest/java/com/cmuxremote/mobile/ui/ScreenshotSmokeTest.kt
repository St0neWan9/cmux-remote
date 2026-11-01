package com.cmuxremote.mobile.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import com.cmuxremote.mobile.data.FeedItem
import com.cmuxremote.mobile.data.FeedOption
import com.cmuxremote.mobile.data.FeedQuestion
import com.cmuxremote.mobile.ui.theme.CmuxTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** A rendered page produces pixels, so a layout regression cannot pass silently. */
class ScreenshotSmokeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun theFeedRendersPixels() {
        compose.setContent {
            CmuxTheme {
                FeedScreen(
                    items = listOf(
                        FeedItem(
                            requestID = "r", kind = "question", status = "pending", title = "Pick",
                            questions = listOf(
                                FeedQuestion(
                                    prompt = "Which?",
                                    options = listOf("A"),
                                    multiSelect = false,
                                    optionDetails = listOf(FeedOption("a", "A", null)),
                                ),
                            ),
                        ),
                    ),
                    onBack = null,
                    onAnswer = { _, _ -> },
                    onDecide = { _, _, _ -> },
                )
            }
        }
        val bitmap = compose.onNodeWithTag("feed.page").captureToImage().asAndroidBitmap()
        assertTrue(bitmap.width > 0 && bitmap.height > 0)
    }
}
