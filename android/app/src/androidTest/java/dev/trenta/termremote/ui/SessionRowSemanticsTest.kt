package dev.trenta.termremote.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import dev.trenta.termremote.model.SessionItem
import dev.trenta.termremote.model.SessionTrailing
import dev.trenta.termremote.ui.components.SessionRow
import dev.trenta.termremote.ui.theme.TermRemoteTheme
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
            TermRemoteTheme {
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
