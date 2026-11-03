package com.cmuxremote.mobile.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.cmuxremote.mobile.data.FeedOption
import com.cmuxremote.mobile.data.FeedQuestion
import com.cmuxremote.mobile.data.FeedItem
import com.cmuxremote.mobile.ui.theme.CmuxTheme
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
            CmuxTheme { FeedScreen(items = listOf(question("req1", "pending")), onBack = null, onAnswer = { _, _ -> }, onDecide = { _, _, _ -> }) }
        }
        compose.onNodeWithTag("feed.question.req1.submit").assertIsDisplayed()
    }

    @Test
    fun resolvedQuestionIsARecordWithoutActions() {
        compose.setContent {
            CmuxTheme { FeedScreen(items = listOf(question("req2", "resolved")), onBack = null, onAnswer = { _, _ -> }, onDecide = { _, _, _ -> }) }
        }
        compose.onNodeWithTag("feed.history.toggle").performClick()
        compose.onNodeWithTag("feed.question.req2.submit").assertDoesNotExist()
    }
}
