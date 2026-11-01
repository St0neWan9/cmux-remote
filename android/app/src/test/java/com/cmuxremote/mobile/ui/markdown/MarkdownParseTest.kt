package com.cmuxremote.mobile.ui.markdown

import org.junit.Assert.assertEquals
import org.junit.Test

/** Block kinds produced by the transcript Markdown parser, without Compose rendering. */
class MarkdownParseTest {
    private fun kinds(text: String): List<String> = markdownBlocksForTest(text)

    @Test
    fun fencedCodeBecomesOneCodeBlock() {
        assertEquals(listOf("code"), kinds("```kotlin\nval x = 1\n```"))
    }

    @Test
    fun headingsReportTheirLevels() {
        assertEquals(
            listOf("h1", "h2", "h3", "h4", "h5", "h6"),
            kinds("# one\n## two\n### three\n#### four\n##### five\n###### six"),
        )
    }

    @Test
    fun unorderedMarkersAllBecomeBullets() {
        assertEquals(listOf("ul", "ul", "ul"), kinds("- one\n* two\n+ three"))
    }

    @Test
    fun orderedItemsStayOrderedListBlocks() {
        assertEquals(listOf("ol", "ol"), kinds("1. one\n2. two"))
    }

    @Test
    fun pipeTableBecomesOneTableBlock() {
        assertEquals(
            listOf("table"),
            kinds("| a | b |\n| --- | --- |\n| 1 | 2 |"),
        )
    }

    @Test
    fun tableDelimitersKeepTheirColumnAlignment() {
        assertEquals(
            listOf("start", "center", "end"),
            markdownTableAlignmentsForTest("| a | b | c |\n| --- | :---: | ---: |\n| 1 | 2 | 3 |"),
        )
    }

    @Test
    fun adjacentProseLinesFormOneParagraph() {
        assertEquals(listOf("p"), kinds("first line\nsecond line"))
    }

    @Test
    fun multiBlockDocumentKeepsSourceOrder() {
        val text = "# Title\n\nintro\n\n- one\n- two\n\n1. first\n2. second\n\n" +
            "```\nval x = 1\n```\n\n| a | b |\n| --- | --- |\n| 1 | 2 |"

        assertEquals(
            listOf("h1", "p", "ul", "ul", "ol", "ol", "code", "table"),
            kinds(text),
        )
    }

    @Test
    fun emptyStringHasNoBlocks() {
        assertEquals(emptyList<String>(), kinds(""))
    }

    @Test
    fun pipeInsideInlineCodeDoesNotStartATable() {
        assertEquals(listOf("p"), kinds("Run `a|b` then continue"))
    }

    @Test
    fun tableWithoutDelimiterRowStaysAParagraph() {
        assertEquals(listOf("p"), kinds("| a | b |\n| 1 | 2 |"))
    }
}
