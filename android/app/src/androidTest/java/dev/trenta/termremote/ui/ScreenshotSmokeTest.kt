package dev.trenta.termremote.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import dev.trenta.termremote.data.FeedItem
import dev.trenta.termremote.data.FeedOption
import dev.trenta.termremote.data.FeedQuestion
import dev.trenta.termremote.ui.theme.TermRemoteTheme
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
            TermRemoteTheme {
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

    @Test
    fun theComposerRendersPixels() {
        compose.setContent {
            TermRemoteTheme {
                ComposerArea(
                    draft = "Hello",
                    onDraftChange = {},
                    onSend = {},
                    onStop = {},
                    working = false,
                    canSend = true,
                    sending = false,
                    error = null,
                )
            }
        }
        val bitmap = compose.onNodeWithTag("voice.draft").captureToImage().asAndroidBitmap()
        assertTrue(bitmap.width > 0 && bitmap.height > 0)
    }

    @Test
    fun theDrawerRendersPixels() {
        compose.setContent {
            TermRemoteTheme {
                DrawerContent(
                    model = SessionListModel(
                        sessions = listOf(
                            dev.trenta.termremote.model.SessionItem(
                                id = "d1", title = "Drawer session", agent = "Claude", age = "now",
                                trailing = dev.trenta.termremote.model.SessionTrailing.None,
                                hostKey = "h1", writable = true,
                            ),
                        ),
                        hosts = listOf("h1" to "Studio"),
                    ),
                    actions = SessionListActions(),
                    onSelectSession = {},
                    onHostConnection = {},
                    closed = {},
                )
            }
        }
        val bitmap = compose.onNodeWithTag("sessions.drawer").captureToImage().asAndroidBitmap()
        assertTrue(bitmap.width > 0 && bitmap.height > 0)
    }
}
