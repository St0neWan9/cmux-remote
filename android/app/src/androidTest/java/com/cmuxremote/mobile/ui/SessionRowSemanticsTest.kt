package com.cmuxremote.mobile.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.cmuxremote.mobile.model.SessionItem
import com.cmuxremote.mobile.model.SessionTrailing
import com.cmuxremote.mobile.ui.components.SessionRow
import com.cmuxremote.mobile.ui.theme.CmuxTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** A session row is one labeled target, and a tap reaches the list. */
class SessionRowSemanticsTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun aSessionRowIsOneTappableTarget() {
        var tapped = false
        compose.setContent {
            CmuxTheme {
                SessionRow(
                    session = SessionItem(
                        id = "s1",
                        title = "Build the thing",
                        agent = "Claude",
                        age = "3m ago",
                        trailing = SessionTrailing.Working,
                        hostKey = "h1",
                        writable = true,
                        working = true,
                    ),
                    selected = false,
                    onClick = { tapped = true },
                )
            }
        }
        compose.onNodeWithTag("session.s1").assertIsDisplayed().performClick()
        assertTrue(tapped)
    }
}
