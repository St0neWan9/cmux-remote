package com.cmuxremote.mobile.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.platform.app.InstrumentationRegistry
import com.cmuxremote.mobile.ConversationUi
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.data.SessionDescriptor
import com.cmuxremote.mobile.ui.theme.CmuxTheme
import org.junit.Rule
import org.junit.Test

/** The composer's status line: a running turn's time, otherwise "Updating…" while the page catches up, as on iPhone. */
class ConversationStatusLineTest {
    @get:Rule
    val compose = createComposeRule()

    private val text = InstrumentationRegistry.getInstrumentation().targetContext
    private fun session(state: String) = SessionDescriptor(
        id = "tui:s", agent = "claude", title = "Build", cwd = "/project", workspaceID = "w", surfaceID = "t",
        state = state, updatedAt = null, resumable = false,
    )
    private fun show(state: ConversationUi, connecting: Boolean = false, offline: Boolean = false) {
        compose.setContent {
            CmuxTheme {
                ConversationScreen(state = state, onBack = null, onDraft = {}, onSend = {}, onStop = {}, connecting = connecting, offline = offline)
            }
        }
    }

    @Test
    fun aPageCatchingUpSaysItIsUpdatingAboveTheComposer() {
        show(ConversationUi(session = session("idle"), messages = emptyList(), loading = false, updating = true))
        compose.onNodeWithTag("connection.updating").assertIsDisplayed()
        compose.onNodeWithText(text.getString(R.string.chat_updating)).assertIsDisplayed()
    }

    @Test
    fun aRunningTurnKeepsItsTimeWhileThePageUpdates() {
        show(ConversationUi(session = session("working"), messages = emptyList(), loading = false, updating = true), connecting = true)
        compose.onNodeWithTag("connection.updating").assertDoesNotExist()
        compose.onNodeWithText(text.getString(R.string.common_working)).assertIsDisplayed()
    }

    @Test
    fun aDialingLinkIsUpdatingNotAPillAtTheTop() {
        show(ConversationUi(session = session("idle"), messages = emptyList(), loading = false), connecting = true, offline = true)
        compose.onNodeWithTag("connection.updating").assertIsDisplayed()
        compose.onNodeWithText(text.getString(R.string.chat_reconnecting)).assertDoesNotExist()
        compose.onNodeWithText(text.getString(R.string.chat_connection_lost)).assertDoesNotExist()
    }

    @Test
    fun aFailedLinkKeepsItsRetryAtTheTopAndNoUpdatingLine() {
        show(ConversationUi(session = session("idle"), messages = emptyList(), loading = false), offline = true)
        compose.onNodeWithText(text.getString(R.string.chat_connection_lost)).assertIsDisplayed()
        compose.onNodeWithTag("connection.updating").assertDoesNotExist()
    }
}
