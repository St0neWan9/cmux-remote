package com.cmuxremote.mobile.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.cmuxremote.mobile.R
import com.cmuxremote.mobile.ui.components.FloatingSurface
import com.cmuxremote.mobile.ui.theme.MobileDesign

/** A question from the Feed, with every option the Mac reported. */
data class FeedQuestionOption(val id: String?, val label: String, val description: String?)

data class FeedQuestionForm(
    val prompt: String,
    val options: List<FeedQuestionOption>,
    val multiSelect: Boolean,
    val allowCustom: Boolean,
    val allowSkip: Boolean,
)

/** One question's answer while the form is being filled in. */
private data class QuestionAnswer(
    val selected: Set<Int> = emptySet(),
    val custom: String = "",
) {
    /** The Bridge wants one label per question; multi-select labels keep the Mac's separator. */
    fun label(question: FeedQuestionForm): String? {
        val typed = custom.trim()
        if (typed.isNotEmpty()) return typed
        val labels = question.options.filterIndexed { index, _ -> index in selected }.map { it.label }
        return labels.takeIf { it.isNotEmpty() }?.joinToString(", ")
    }
}

/**
 * Collects one label-based answer per question, in the order the Mac supplied them.
 * A record view passes the answered labels instead, so the same rows show what was chosen.
 */
@Composable
fun QuestionFormCard(
    questions: List<FeedQuestionForm>,
    busy: Boolean,
    answered: List<String>?,
    onSubmit: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val drafts = remember(questions) { mutableStateMapOf<Int, QuestionAnswer>() }
    val record = answered
    val answers = if (record != null) {
        questions.indices.mapNotNull { index -> record.getOrNull(index)?.takeIf { it.isNotBlank() } }
    } else {
        questions.indices.mapNotNull { index -> drafts[index]?.label(questions[index]) }
    }
    // A request that cannot be skipped needs one answer per question before it can be sent.
    val missingRequired = record == null && questions.indices.any { index ->
        !questions[index].allowSkip && drafts[index]?.label(questions[index]) == null
    }
    // A prompt with no options is answered by the submit itself; anything else needs a choice.
    val answersNothing = answers.isEmpty() && questions.any { it.options.isNotEmpty() }

    FloatingSurface(modifier = modifier.fillMaxWidth()) {
        if (questions.isEmpty()) {
            Text(stringResource(R.string.feed_no_questions), color = MobileDesign.Muted, style = MaterialTheme.typography.bodyMedium)
        } else {
            questions.forEachIndexed { index, question ->
                if (index > 0) Spacer(Modifier.height(18.dp))
                if (record != null) {
                    val answer = record.getOrNull(index)
                    val (selected, custom) = recordedSelection(question, answer)
                    QuestionBlock(
                        question = question,
                        busy = busy,
                        selected = selected,
                        customText = custom.orEmpty(),
                        readOnly = true,
                        onChoose = {},
                        onCustom = {},
                    )
                    if (answer.isNullOrBlank()) {
                        Text(stringResource(R.string.feed_unanswered), color = MobileDesign.Muted, style = MaterialTheme.typography.labelMedium)
                    }
                } else {
                    val draft = drafts[index]
                    QuestionBlock(
                        question = question,
                        busy = busy,
                        selected = draft?.selected.orEmpty(),
                        customText = draft?.custom.orEmpty(),
                        readOnly = false,
                        onChoose = { optionIndex ->
                            val current = drafts[index] ?: QuestionAnswer()
                            drafts[index] = if (question.multiSelect) {
                                val next = if (optionIndex in current.selected) {
                                    current.selected - optionIndex
                                } else {
                                    current.selected + optionIndex
                                }
                                // Choosing an option replaces any typed custom answer.
                                QuestionAnswer(next, "")
                            } else {
                                QuestionAnswer(setOf(optionIndex), "")
                            }
                        },
                        onCustom = { text ->
                            val current = drafts[index] ?: QuestionAnswer()
                            // Typing a custom answer replaces the option selection, as on the Mac.
                            drafts[index] = if (text.isEmpty()) {
                                QuestionAnswer(current.selected, "")
                            } else {
                                QuestionAnswer(emptySet(), text)
                            }
                        },
                    )
                }
            }

            if (record == null) {
                Spacer(Modifier.height(18.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Button(
                        onClick = { onSubmit(answers) },
                        enabled = !busy && !missingRequired && !answersNothing,
                        shape = CircleShape,
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MobileDesign.Accent,
                            contentColor = MobileDesign.Canvas,
                        ),
                    ) {
                        Text(stringResource(R.string.feed_submit_answer), maxLines = 1)
                    }
                    if (questions.any { it.allowSkip }) {
                        OutlinedButton(
                            onClick = { onSubmit(emptyList()) },
                            enabled = !busy,
                            shape = CircleShape,
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                        ) {
                            Text(stringResource(R.string.feed_skip_question), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

/** A permission request with a bounded default and its wider grants kept behind an explicit confirmation. */
@Composable
fun PermissionDecisionCard(
    title: String,
    subject: String?,
    busy: Boolean,
    onDecide: (mode: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<String?>(null) }

    FloatingSurface(modifier = modifier.fillMaxWidth()) {
        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium)
        if (!subject.isNullOrBlank()) {
            Spacer(Modifier.height(8.dp))
            Surface(color = MobileDesign.Code, shape = RoundedCornerShape(12.dp)) {
                Text(
                    text = subject,
                    color = MobileDesign.Muted,
                    style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = { onDecide("once") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MobileDesign.Accent,
                    contentColor = MobileDesign.Canvas,
                ),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_allow_once), maxLines = 1)
            }
            OutlinedButton(
                onClick = { onDecide("deny") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_deny), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
            }
        }
        if (PermissionWiderModes.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            Box {
                TextButton(
                    onClick = { expanded = true },
                    enabled = !busy,
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 4.dp),
                ) {
                    Text(
                        stringResource(R.string.feed_more_decisions),
                        color = MobileDesign.Muted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Icon(
                        Icons.Rounded.ArrowDropDown,
                        contentDescription = null,
                        tint = MobileDesign.Muted,
                        modifier = Modifier.size(16.dp),
                    )
                }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    PermissionWiderModes.forEach { mode ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    permissionModeLabel(mode),
                                    color = MobileDesign.Ink,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            },
                            onClick = {
                                expanded = false
                                confirming = mode
                            },
                        )
                    }
                }
            }
        }
    }

    val mode = confirming
    if (mode != null) {
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text(stringResource(R.string.feed_confirm_decision), color = MobileDesign.Ink) },
            text = {
                Text(
                    permissionExplanation(mode),
                    color = MobileDesign.Ink,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = null
                    onDecide(mode)
                }) {
                    Text(stringResource(R.string.feed_use_decision))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null }) {
                    Text(stringResource(R.string.common_cancel), color = MobileDesign.Muted)
                }
            },
        )
    }
}

/** A plan awaiting approval; feedback is sent only when the user typed some. */
@Composable
fun PlanDecisionCard(
    title: String,
    plan: String?,
    busy: Boolean,
    onDecide: (mode: String, feedback: String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var feedback by remember { mutableStateOf("") }
    val send: (String) -> Unit = { mode ->
        onDecide(mode, feedback.trim().takeIf { it.isNotEmpty() })
    }

    FloatingSurface(modifier = modifier.fillMaxWidth()) {
        Text(title, color = MobileDesign.Ink, style = MaterialTheme.typography.titleMedium)
        if (!plan.isNullOrBlank()) {
            Spacer(Modifier.height(10.dp))
            Surface(color = MobileDesign.Code, shape = RoundedCornerShape(12.dp)) {
                Text(
                    text = plan,
                    color = MobileDesign.Ink,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = feedback,
            onValueChange = { feedback = it },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.feed_plan_feedback_placeholder), color = MobileDesign.Muted) },
            minLines = 1,
            maxLines = 4,
            shape = RoundedCornerShape(14.dp),
        )
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = { send("bypassPermissions") },
            enabled = !busy,
            shape = CircleShape,
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MobileDesign.Accent,
                contentColor = MobileDesign.Canvas,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.feed_execute_plan), maxLines = 1)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { send("autoAccept") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_auto_accept), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
            }
            OutlinedButton(
                onClick = { send("manual") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_continue_after_edit), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { send("ultraplan") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_deep_plan), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
            }
            OutlinedButton(
                onClick = { send("deny") },
                enabled = !busy,
                shape = CircleShape,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.feed_deny), color = if (busy) MobileDesign.Muted else MobileDesign.Ink, maxLines = 1)
            }
        }
    }
}

@Composable
private fun QuestionBlock(
    question: FeedQuestionForm,
    busy: Boolean,
    selected: Set<Int>,
    customText: String,
    readOnly: Boolean,
    onChoose: (Int) -> Unit,
    onCustom: (String) -> Unit,
) {
    val enabled = !busy && !readOnly
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(question.prompt, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyLarge)
        question.options.forEachIndexed { optionIndex, option ->
            val isSelected = optionIndex in selected
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = enabled) { onChoose(optionIndex) }
                    .heightIn(min = MobileDesign.Control),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (question.multiSelect) {
                    Checkbox(
                        checked = isSelected,
                        onCheckedChange = { onChoose(optionIndex) },
                        enabled = enabled,
                        colors = CheckboxDefaults.colors(
                            checkedColor = MobileDesign.Accent,
                            uncheckedColor = MobileDesign.Muted,
                        ),
                    )
                } else {
                    RadioButton(
                        selected = isSelected,
                        onClick = { onChoose(optionIndex) },
                        enabled = enabled,
                        colors = RadioButtonDefaults.colors(
                            selectedColor = MobileDesign.Accent,
                            unselectedColor = MobileDesign.Muted,
                        ),
                    )
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(option.label, color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
                    val description = option.description
                    if (!description.isNullOrBlank()) {
                        Text(
                            description,
                            color = MobileDesign.Muted,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
        }
        if (readOnly && customText.isNotBlank()) {
            Text(stringResource(R.string.feed_other_answer, customText), color = MobileDesign.Ink, style = MaterialTheme.typography.bodyMedium)
        }
        if (!readOnly && question.allowCustom) {
            OutlinedTextField(
                value = customText,
                onValueChange = onCustom,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(stringResource(R.string.feed_other_placeholder), color = MobileDesign.Muted) },
                minLines = 1,
                maxLines = 4,
                shape = RoundedCornerShape(14.dp),
            )
        }
    }
}

/** Matches a recorded answer back to the option rows; a label none of them carry was custom text. */
private fun recordedSelection(question: FeedQuestionForm, answer: String?): Pair<Set<Int>, String?> {
    if (answer.isNullOrBlank()) return emptySet<Int>() to null
    if (!question.multiSelect) {
        val index = question.options.indexOfFirst { it.label == answer }
        return if (index >= 0) setOf(index) to null else emptySet<Int>() to answer
    }
    val labels = answer.split(", ").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    val indexes = question.options.indices.filter { question.options[it].label in labels }.toSet()
    return if (indexes.isEmpty()) emptySet<Int>() to answer else indexes to null
}

private val PermissionWiderModes: List<String> = listOf("always", "all", "bypass")

@Composable
private fun permissionModeLabel(mode: String): String = when (mode) {
    "always" -> stringResource(R.string.feed_mode_always_label)
    "all" -> stringResource(R.string.feed_mode_all_label)
    "bypass" -> stringResource(R.string.feed_mode_bypass_label)
    else -> mode
}

@Composable
private fun permissionExplanation(mode: String): String = when (mode) {
    "always" -> stringResource(R.string.feed_mode_always_explanation)
    "all" -> stringResource(R.string.feed_mode_all_explanation)
    "bypass" -> stringResource(R.string.feed_mode_bypass_explanation)
    else -> ""
}
