package dev.trenta.termremote.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import dev.trenta.termremote.data.FeedOption
import dev.trenta.termremote.data.FeedQuestion
import dev.trenta.termremote.data.FeedItem
import dev.trenta.termremote.ui.theme.TermRemoteTheme
import org.junit.Rule
import org.junit.Test

/** A pending event is answerable; a resolved one is only a record. */
class FeedSemanticsTest {
    @get:Rule
    val compose = createComposeRule()

    private fun question(id: String, status: String) = FeedItem(
        requestID = id,
        kind = "question",
        status = status,
        title = "Pick one",
        questions = listOf(
            FeedQuestion(
                prompt = "Which?",
                options = listOf("A", "B"),
                multiSelect = false,
                optionDetails = listOf(FeedOption("a", "A", null), FeedOption("b", "B", null)),
            ),
        ),
    )

    @Test
    fun pendingQuestionShowsItsSubmitAction() {
        compose.setContent {
            TermRemoteTheme { FeedScreen(items = listOf(question("req1", "pending")), onBack = null, onAnswer = { _, _ -> }, onDecide = { _, _, _ -> }) }
        }
        compose.onNodeWithTag("feed.question.req1.submit").assertIsDisplayed()
    }

    @Test
    fun resolvedQuestionIsARecordWithoutActions() {
        compose.setContent {
            TermRemoteTheme { FeedScreen(items = listOf(question("req2", "resolved")), onBack = null, onAnswer = { _, _ -> }, onDecide = { _, _, _ -> }) }
        }
        compose.onNodeWithTag("feed.history.toggle").performClick()
        compose.onNodeWithTag("feed.question.req2.submit").assertDoesNotExist()
    }
}
