package com.cmuxremote.mobile.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.model.SessionItem
import com.cmuxremote.mobile.model.SessionTrailing
import com.cmuxremote.mobile.ui.components.SessionRow
import com.cmuxremote.mobile.ui.components.WorkingIndicator
import com.cmuxremote.mobile.ui.theme.CmuxTheme
import org.junit.Rule
import org.junit.Test

/** Shared components keep their identifiers and stay readable at large font scales. */
class ComponentSemanticsTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun theWorkingIndicatorIsLabeled() {
        compose.setContent { CmuxTheme { WorkingIndicator() } }
        compose.onNodeWithTag("chat.working").assertIsDisplayed()
    }

    @Test
    fun theResponseFooterOffersEveryAction() {
        compose.setContent {
            CmuxTheme {
                ResponseFooter(
                    completedAt = null,
                    onCopy = {},
                    onShare = {},
                    onQuote = {},
                    onSelectText = {},
                )
            }
        }
        compose.onNodeWithTag("response.copy").assertIsDisplayed()
        compose.onNodeWithTag("response.share").assertIsDisplayed()
        compose.onNodeWithTag("response.quote").assertIsDisplayed()
        compose.onNodeWithTag("response.select").assertIsDisplayed()
    }

    @Test
    fun theDrawerCarriesTheTreeAndItsMacs() {
        compose.setContent {
            CmuxTheme {
                DrawerContent(
                    model = SessionListModel(
                        sessions = listOf(
                            SessionItem(
                                id = "d1",
                                title = "Drawer session",
                                agent = "Claude",
                                age = "now",
                                trailing = SessionTrailing.None,
                                hostKey = "h1",
                                writable = true,
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
        compose.onNodeWithTag("sessions.drawer").assertIsDisplayed()
        compose.onNodeWithText("Drawer session").assertIsDisplayed()
        compose.onNodeWithText("Studio").assertIsDisplayed()
    }

    @Test
    fun thePushTransitionShowsItsPage() {
        compose.setContent { CmuxTheme { PushIn { androidx.compose.material3.Text("pushed page") } } }
        compose.waitForIdle()
        compose.onNodeWithText("pushed page").assertIsDisplayed()
    }

    @Test
    fun aMarkdownTableRendersItsCells() {
        compose.setContent {
            CmuxTheme {
                com.cmuxremote.mobile.ui.markdown.MarkdownText("| Name | Value |\n| --- | --- |\n| Alpha | 7 |")
            }
        }
        compose.onNodeWithText("Alpha").assertIsDisplayed()
        compose.onNodeWithText("7").assertIsDisplayed()
    }

    @Test
    fun backgroundTasksCollapseToASummaryUntilOpened() {
        compose.setContent {
            CmuxTheme {
                BackgroundTasksRow(
                    tasks = listOf(BackgroundTask(id = "t1", tool = "Shell", status = "running", running = true)),
                    onOpen = {},
                )
            }
        }
        compose.onNodeWithTag("chat.background").assertIsDisplayed()
        compose.onNodeWithText("Shell").assertDoesNotExist()
        compose.onNodeWithTag("chat.background").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Shell").assertIsDisplayed()
    }

    @Test
    fun aSelectedPillAnnouncesItsState() {
        compose.setContent {
            CmuxTheme {
                com.cmuxremote.mobile.ui.components.Pill(
                    text = "All",
                    modifier = androidx.compose.ui.Modifier.testTag("pill.all"),
                    selected = true,
                )
            }
        }
        compose.onNodeWithTag("pill.all").assertIsSelected()
    }





    @Test
    fun theComposerTakesFocusOnTap() {
        compose.setContent {
            CmuxTheme {
                ComposerArea(
                    draft = "",
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
        compose.onNodeWithTag("chat.composer").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("chat.composer").assertIsFocused()
    }

    @Test
    fun aSessionRowStaysReadableAtDoubleFontScale() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density = density.density, fontScale = 2f),
            ) {
                CmuxTheme {
                    SessionRow(
                        session = SessionItem(
                            id = "big",
                            title = "A title that must not vanish",
                            agent = "Claude",
                            age = "3m ago",
                            trailing = SessionTrailing.Working,
                            hostKey = "h1",
                            writable = true,
                            working = true,
                        ),
                        selected = false,
                        onClick = {},
                    )
                }
            }
        }
        compose.onNodeWithText("A title that must not vanish").assertIsDisplayed()
    }
}
