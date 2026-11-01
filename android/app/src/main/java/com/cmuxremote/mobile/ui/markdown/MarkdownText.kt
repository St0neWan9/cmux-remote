package com.cmuxremote.mobile.ui.markdown

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cmuxremote.mobile.ui.theme.MobileDesign

/**
 * Native Markdown prose for the Android transcript.
 *
 * The text is parsed once per message into blocks (the same block model as the iOS
 * `MarkdownBlock` parser) and rendered with Compose primitives: no Markdown package
 * and no platform Markdown parser. Inline styles are parsed once per block as well.
 */
@Composable
fun MarkdownText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = MobileDesign.Ink,
    selectable: Boolean = true,
) {
    val blocks = remember(text) { parseMarkdownBlocks(text) }
    if (selectable) {
        SelectionContainer {
            MarkdownColumn(blocks = blocks, color = color, modifier = modifier)
        }
    } else {
        MarkdownColumn(blocks = blocks, color = color, modifier = modifier)
    }
}

/** Block kinds only, for a JVM test that asserts parsing without pulling in Compose rendering. */
internal fun markdownBlocksForTest(text: String): List<String> = parseMarkdownBlocks(text).map { it.kind }

/** Alignment names for the first table, so a parser test can see what the delimiters said. */
internal fun markdownTableAlignmentsForTest(text: String): List<String> {
    val table = parseMarkdownBlocks(text).filterIsInstance<MarkdownBlock.Table>().firstOrNull() ?: return emptyList()
    return table.alignments.map {
        when (it) {
            androidx.compose.ui.text.style.TextAlign.Center -> "center"
            androidx.compose.ui.text.style.TextAlign.End -> "end"
            else -> "start"
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Block model and parser
// ---------------------------------------------------------------------------------------------

private sealed interface MarkdownBlock {
    data class Code(val text: String) : MarkdownBlock
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class Bullet(val text: String) : MarkdownBlock
    data class Ordered(val marker: String, val text: String) : MarkdownBlock
    data class Table(
        val header: List<String>,
        val rows: List<List<String>>,
        /** Alignment from the delimiter row: start, center or end for each column. */
        val alignments: List<androidx.compose.ui.text.style.TextAlign> =
            List(header.size) { androidx.compose.ui.text.style.TextAlign.Start },
    ) : MarkdownBlock
    data class Paragraph(val text: String) : MarkdownBlock
}

private val MarkdownBlock.kind: String
    get() = when (this) {
        is MarkdownBlock.Code -> "code"
        is MarkdownBlock.Heading -> "h$level"
        is MarkdownBlock.Bullet -> "ul"
        is MarkdownBlock.Ordered -> "ol"
        is MarkdownBlock.Table -> "table"
        is MarkdownBlock.Paragraph -> "p"
    }

private fun parseMarkdownBlocks(text: String): List<MarkdownBlock> {
    val blocks = mutableListOf<MarkdownBlock>()
    // Splitting on the fence keeps every even segment as prose and every odd segment as code.
    text.split("```").forEachIndexed { index, segment ->
        if (index % 2 == 1) {
            val code = fenceBody(segment)
            if (code.isNotEmpty()) blocks.add(MarkdownBlock.Code(code))
        } else {
            parseProse(segment, blocks)
        }
    }
    return blocks
}

/** Drops the optional language line that follows the opening fence, then the fence padding. */
private fun fenceBody(segment: String): String {
    val newline = segment.indexOf('\n')
    val body = if (newline >= 0) segment.substring(newline + 1) else segment
    return body.trim { it == '\n' || it == '\r' }
}

private fun parseProse(content: String, blocks: MutableList<MarkdownBlock>) {
    val lines = content.split("\n")
    val paragraph = mutableListOf<String>()

    fun flushParagraph() {
        if (paragraph.isEmpty()) return
        blocks.add(MarkdownBlock.Paragraph(paragraph.joinToString("\n")))
        paragraph.clear()
    }

    var position = 0
    while (position < lines.size) {
        val line = lines[position]

        val table = if (isTableRow(line)) parseTableAt(lines, position) else null
        if (table != null) {
            flushParagraph()
            blocks.add(table.block)
            position = table.nextIndex
            continue
        }

        val structural = structure(line)
        if (line.isBlank() || structural != null) {
            flushParagraph()
            if (structural != null) blocks.add(structural)
        } else {
            paragraph.add(line)
        }
        position++
    }
    flushParagraph()
}

private data class ParsedTable(val block: MarkdownBlock.Table, val nextIndex: Int)

/** A header row plus a delimiter row, followed by every consecutive pipe row. */
private fun parseTableAt(lines: List<String>, start: Int): ParsedTable? {
    if (start + 1 >= lines.size) return null
    val header = tableCells(lines[start]) ?: return null
    val delimiter = tableCells(lines[start + 1]) ?: return null
    if (header.isEmpty() || header.size != delimiter.size) return null
    if (!delimiter.all(::isDelimiterCell)) return null

    var end = start + 2
    while (end < lines.size && isTableRow(lines[end])) end++

    val rows = (start + 2 until end).mapNotNull { index ->
        val cells = tableCells(lines[index]) ?: return@mapNotNull null
        List(header.size) { column -> cells.getOrElse(column) { "" } }
    }
    val alignments = delimiter.map { cell ->
        val rule = cell.trim()
        when {
            rule.startsWith(":") && rule.endsWith(":") -> androidx.compose.ui.text.style.TextAlign.Center
            rule.endsWith(":") -> androidx.compose.ui.text.style.TextAlign.End
            else -> androidx.compose.ui.text.style.TextAlign.Start
        }
    }
    return ParsedTable(MarkdownBlock.Table(header, rows, alignments), end)
}

private fun isTableRow(line: String): Boolean = tableCells(line) != null

private fun isDelimiterCell(cell: String): Boolean {
    val rule = cell.trim()
    return rule.isNotEmpty() && rule.all { it == '-' || it == ':' } && rule.contains('-')
}

/**
 * Splits a GitHub-style pipe row on unescaped pipes outside inline code and drops the
 * optional outer pipes, mirroring `MarkdownTable.cells` in the shared Swift core.
 */
private fun tableCells(line: String): List<String>? {
    val trimmed = line.trim()
    if ('|' !in trimmed) return null

    val cells = mutableListOf<String>()
    val current = StringBuilder()
    var inCode = false
    var escaped = false
    for (character in trimmed) {
        if (escaped) {
            current.append(character)
            escaped = false
            continue
        }
        when {
            character == '\\' -> {
                escaped = true
                current.append(character)
            }
            character == '`' -> {
                inCode = !inCode
                current.append(character)
            }
            character == '|' && !inCode -> {
                cells.add(current.toString())
                current.clear()
            }
            else -> current.append(character)
        }
    }
    cells.add(current.toString())

    if (trimmed.startsWith("|")) cells.removeAt(0)
    if (trimmed.endsWith("|") && !trimmed.endsWith("\\|") && cells.isNotEmpty()) {
        cells.removeAt(cells.lastIndex)
    }
    if (cells.isEmpty()) return null
    return cells.map { it.trim().replace("\\|", "|") }
}

/** Heading, bullet or ordered-list marker, or null for a normal prose line. */
private fun structure(line: String): MarkdownBlock? {
    if (line.takeWhile { it == ' ' }.length > 3) return null
    val trimmed = line.trim()
    if (trimmed.isEmpty()) return null

    val hashes = trimmed.takeWhile { it == '#' }.length
    if (hashes in 1..6 && trimmed.length > hashes && trimmed[hashes] == ' ') {
        return MarkdownBlock.Heading(hashes, trimmed.substring(hashes + 1).trimStart())
    }

    for (prefix in listOf("- ", "* ", "+ ")) {
        if (trimmed.startsWith(prefix)) return MarkdownBlock.Bullet(trimmed.substring(prefix.length))
    }

    val digits = trimmed.takeWhile { it.isDigit() }
    if (digits.isNotEmpty() && trimmed.startsWith(". ", digits.length)) {
        return MarkdownBlock.Ordered("$digits.", trimmed.substring(digits.length + 2))
    }
    return null
}

// ---------------------------------------------------------------------------------------------
// Block rendering
// ---------------------------------------------------------------------------------------------

@Composable
private fun MarkdownColumn(blocks: List<MarkdownBlock>, color: Color, modifier: Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        blocks.forEach { block ->
            when (block) {
                is MarkdownBlock.Code -> MarkdownCodeBlock(block.text, color)
                is MarkdownBlock.Heading -> MarkdownHeading(block, color)
                is MarkdownBlock.Bullet -> MarkdownListItem("•", block.text, color)
                is MarkdownBlock.Ordered -> MarkdownListItem(block.marker, block.text, color)
                is MarkdownBlock.Table -> MarkdownTableBlock(block, color)
                is MarkdownBlock.Paragraph -> MarkdownParagraph(block.text, color)
            }
        }
    }
}

@Composable
private fun MarkdownCodeBlock(code: String, color: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(MobileDesign.Soft, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Text(
            text = code,
            color = color,
            fontFamily = FontFamily.Monospace,
            fontSize = 12.sp,
            lineHeight = 18.sp,
        )
    }
}

@Composable
private fun MarkdownHeading(block: MarkdownBlock.Heading, color: Color) {
    val size = when (block.level) {
        1 -> 20.sp
        2 -> 18.sp
        3 -> 16.sp
        4 -> 15.sp
        5 -> 14.sp
        else -> 13.sp
    }
    Text(
        text = rememberInline(block.text),
        color = color,
        fontSize = size,
        lineHeight = (size.value + 6).sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier
            .fillMaxWidth()
            .semantics { heading() },
    )
}

@Composable
private fun MarkdownParagraph(text: String, color: Color) {
    Text(
        text = rememberInline(text),
        color = color,
        fontSize = 16.sp,
        lineHeight = 23.sp,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun MarkdownListItem(marker: String, text: String, color: Color) {
    Row(Modifier.fillMaxWidth()) {
        Text(
            text = marker,
            color = color,
            fontSize = 16.sp,
            lineHeight = 23.sp,
            modifier = Modifier.width(16.dp),
        )
        Text(
            text = rememberInline(text),
            color = color,
            fontSize = 16.sp,
            lineHeight = 23.sp,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * Equal-width columns that wrap their cells. The grid uses the parent width when it fits;
 * a horizontal scroller appears only when every column would be narrower than its minimum.
 */
@Composable
private fun MarkdownTableBlock(block: MarkdownBlock.Table, color: Color) {
    val columns = block.header.size
    if (columns == 0) return

    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val available = if (maxWidth.value.isFinite()) maxWidth else 600.dp
        val measurer = androidx.compose.ui.text.rememberTextMeasurer()
        val density = androidx.compose.ui.platform.LocalDensity.current
        val cellStyle = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, lineHeight = 20.sp)
        val horizontalPadding = with(density) { 20.dp.toPx() }

        // Natural width keeps a short column short instead of giving every column
        // the same share; the minimum is the longest unbreakable word.
        val natural = List(columns) { column ->
            val cells = listOf(block.header[column]) + block.rows.map { it.getOrElse(column) { "" } }
            cells.maxOfOrNull { cell ->
                measurer.measure(androidx.compose.ui.text.AnnotatedString(cell), style = cellStyle, maxLines = 1, softWrap = false)
                    .size.width.toFloat()
            }?.plus(horizontalPadding) ?: horizontalPadding
        }
        val minimum = List(columns) { column ->
            val cells = listOf(block.header[column]) + block.rows.map { it.getOrElse(column) { "" } }
            cells.flatMap { it.split(Regex("\\s+")) }
                .maxOfOrNull { word ->
                    measurer.measure(androidx.compose.ui.text.AnnotatedString(word), style = cellStyle, maxLines = 1, softWrap = false)
                        .size.width.toFloat()
                }?.plus(horizontalPadding) ?: horizontalPadding
        }
        val availablePx = with(density) { available.toPx() }
        val widths = allocateTableWidths(natural, minimum, availablePx)
        val total = widths.sum()
        val scrollable = total > availablePx + 1f
        val scrollState = rememberScrollState()
        val gridModifier = if (scrollable) Modifier.horizontalScroll(scrollState) else Modifier

        SelectionContainer {
            Column(
                modifier = gridModifier.width(with(density) { total.toDp() }),
            ) {
                MarkdownTableRow(
                    block.header,
                    widths.map { with(density) { it.toDp() } },
                    block.alignments,
                    header = true,
                    color = color,
                )
                HorizontalDivider(color = MobileDesign.Line)
                block.rows.forEachIndexed { index, row ->
                    MarkdownTableRow(
                        row,
                        widths.map { with(density) { it.toDp() } },
                        block.alignments,
                        header = false,
                        color = color,
                    )
                    if (index != block.rows.lastIndex) HorizontalDivider(color = MobileDesign.Line)
                }
            }
        }
    }
}

/**
 * Gives every column its natural width when the table fits; otherwise takes the
 * space off the widest columns first, keeping every column at least as wide as
 * its longest word. Only when even those minima overflow does the table scroll.
 */
private fun allocateTableWidths(natural: List<Float>, minimum: List<Float>, available: Float): List<Float> {
    if (natural.isEmpty()) return emptyList()
    val naturalTotal = natural.sum()
    if (naturalTotal <= available) return natural
    val minimumTotal = minimum.sum()
    if (minimumTotal >= available) return minimum
    val extra = available - minimumTotal
    val slack = natural.indices.map { (natural[it] - minimum[it]).coerceAtLeast(0f) }
    val slackTotal = slack.sum().takeIf { it > 0f } ?: return minimum
    return natural.indices.map { minimum[it] + extra * (slack[it] / slackTotal) }
}

@Composable
private fun MarkdownTableRow(
    cells: List<String>,
    columnWidths: List<Dp>,
    alignments: List<androidx.compose.ui.text.style.TextAlign>,
    header: Boolean,
    color: Color,
) {
    Row(Modifier.fillMaxWidth()) {
        cells.forEachIndexed { index, cell ->
            Text(
                text = rememberInline(cell),
                color = color,
                fontSize = 14.sp,
                lineHeight = 20.sp,
                fontWeight = if (header) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = alignments.getOrElse(index) { androidx.compose.ui.text.style.TextAlign.Start },
                modifier = Modifier
                    .width(columnWidths.getOrElse(index) { 88.dp })
                    .padding(horizontal = 10.dp, vertical = 8.dp),
            )
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Inline styles
// ---------------------------------------------------------------------------------------------

@Composable
private fun rememberInline(text: String): AnnotatedString {
    val uriHandler = LocalUriHandler.current
    return remember(text, uriHandler) { inlineMarkdown(text, uriHandler) }
}

private fun inlineMarkdown(text: String, uriHandler: UriHandler): AnnotatedString {
    val linkStyle = SpanStyle(
        color = MobileDesign.Accent,
        textDecoration = TextDecoration.Underline,
    )
    val listener = object : LinkInteractionListener {
        override fun onClick(link: LinkAnnotation) {
            val url = (link as? LinkAnnotation.Url)?.url ?: return
            uriHandler.openUri(url)
        }
    }
    return buildAnnotatedString {
        appendInlineBody(text, SpanStyle(), linkStyle, listener)
    }
}

private fun AnnotatedString.Builder.appendInlineBody(
    text: String,
    span: SpanStyle,
    linkStyle: SpanStyle,
    listener: LinkInteractionListener,
) {
    var index = 0
    var literalStart = 0
    while (index < text.length) {
        val token = inlineTokenAt(text, index)
        if (token == null) {
            index++
            continue
        }
        if (token.start > literalStart) {
            withStyle(span) { append(text.substring(literalStart, token.start)) }
        }
        when {
            token.code -> withStyle(span + inlineCodeStyle()) { append(token.content) }
            token.url != null -> withLink(
                LinkAnnotation.Url(token.url, TextLinkStyles(style = linkStyle), listener),
            ) {
                // The label may itself contain emphasis or code spans.
                appendInlineBody(token.content, span, linkStyle, listener)
            }
            token.style != null -> appendInlineBody(token.content, span + token.style, linkStyle, listener)
            else -> withStyle(span) { append(token.content) }
        }
        index = token.end
        literalStart = index
    }
    if (literalStart < text.length) withStyle(span) { append(text.substring(literalStart)) }
}

/** Built lazily so a JVM parsing test never initializes Compose-backed design tokens. */
private fun inlineCodeStyle(): SpanStyle = SpanStyle(
    fontFamily = FontFamily.Monospace,
    background = MobileDesign.Code,
    color = MobileDesign.Ink,
)

private data class InlineToken(
    val start: Int,
    val end: Int,
    val content: String,
    val style: SpanStyle? = null,
    val code: Boolean = false,
    val url: String? = null,
)

private fun inlineTokenAt(text: String, index: Int): InlineToken? = when {
    text[index] == '`' -> delimited(text, index, 1)?.copy(code = true)
    text.startsWith("**", index) ->
        delimited(text, index, 2)?.copy(style = SpanStyle(fontWeight = FontWeight.Bold))
    text.startsWith("~~", index) ->
        delimited(text, index, 2)?.copy(style = SpanStyle(textDecoration = TextDecoration.LineThrough))
    text[index] == '*' ->
        delimited(text, index, 1)?.copy(style = SpanStyle(fontStyle = FontStyle.Italic))
    text[index] == '[' -> linkToken(text, index)
    else -> null
}

private fun delimited(text: String, start: Int, markerLength: Int): InlineToken? {
    val contentStart = start + markerLength
    val marker = text.substring(start, contentStart)
    val close = text.indexOf(marker, contentStart)
    if (close <= contentStart) return null
    return InlineToken(start, close + markerLength, text.substring(contentStart, close))
}

private fun linkToken(text: String, start: Int): InlineToken? {
    val labelEnd = text.indexOf(']', start + 1)
    if (labelEnd <= start + 1) return null
    if (labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') return null
    val urlEnd = text.indexOf(')', labelEnd + 2)
    if (urlEnd <= labelEnd + 2) return null
    val url = text.substring(labelEnd + 2, urlEnd).trim()
    if (url.isEmpty()) return null
    return InlineToken(start, urlEnd + 1, text.substring(start + 1, labelEnd), url = url)
}
