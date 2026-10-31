package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.jsonBool
import com.cmuxremote.mobile.protocol.jsonObjectOf
import com.cmuxremote.mobile.protocol.jsonString
import com.cmuxremote.mobile.protocol.jsonStringList
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class ProjectReaderTest {
    private data class RecordedCall(val method: String, val path: String, val query: Map<String, String>)

    private val calls = mutableListOf<RecordedCall>()

    private fun makeReader(response: JsonElement): ProjectReader =
        ProjectReader { method, path, query, _ ->
            calls += RecordedCall(method, path, query)
            response
        }

    @Test
    fun changesParsesPorcelainEntriesIncludingRenameAndSpaces() = runTest {
        val entries = listOf(
            " M Sources/Foo.swift",
            "R  old name.swift",
            "new name.swift",
            "A  docs/with space.md",
        )
        val reader = makeReader(jsonObjectOf("entries" to jsonStringList(entries)))

        val changes = reader.changes("session-1")

        assertEquals(listOf("/v2/sessions/session-1/changes"), calls.map { it.path })
        assertEquals(listOf("GET"), calls.map { it.method })
        assertEquals(emptyMap<String, String>(), calls.single().query)
        assertEquals(
            listOf(
                ProjectChange(path = "Sources/Foo.swift", status = " M", added = null, removed = null),
                ProjectChange(path = "old name.swift", status = "R ", added = null, removed = null),
                ProjectChange(path = "docs/with space.md", status = "A ", added = null, removed = null),
            ),
            changes,
        )
    }

    @Test
    fun missingEntriesYieldsAnEmptyList() = runTest {
        val reader = makeReader(jsonObjectOf())

        val changes = reader.changes("session-1")

        assertEquals(emptyList<ProjectChange>(), changes)
        assertEquals(listOf("/v2/sessions/session-1/changes"), calls.map { it.path })
    }

    @Test
    fun diffPassesPathQueryAndDecodesText() = runTest {
        val reader = makeReader(
            jsonObjectOf(
                "path" to jsonString("src/App.kt"),
                "text" to jsonString("@@ -1 +1 @@"),
                "truncated" to jsonBool(true),
            ),
        )

        val text = reader.diff("session-1", "src/App.kt")

        assertEquals(ProjectText(path = "src/App.kt", text = "@@ -1 +1 @@", truncated = true), text)
        assertEquals(listOf("/v2/sessions/session-1/diff"), calls.map { it.path })
        assertEquals(mapOf("path" to "src/App.kt"), calls.single().query)
    }

    @Test
    fun filePassesPathQueryAndDecodesText() = runTest {
        val reader = makeReader(
            jsonObjectOf(
                "path" to jsonString("docs/read me.md"),
                "text" to jsonString("# Hi"),
                "truncated" to jsonBool(false),
            ),
        )

        val text = reader.file("session-1", "docs/read me.md")

        assertEquals(ProjectText(path = "docs/read me.md", text = "# Hi", truncated = false), text)
        assertEquals(listOf("/v2/sessions/session-1/file"), calls.map { it.path })
        assertEquals(mapOf("path" to "docs/read me.md"), calls.single().query)
    }

    @Test
    fun textFallsBackWhenResponseOmitsFields() = runTest {
        val reader = makeReader(jsonObjectOf())

        val text = reader.diff("session-1", "src/App.kt")

        assertEquals(ProjectText(path = "src/App.kt", text = "", truncated = false), text)
    }

    @Test
    fun nonObjectChangeResponseThrowsInvalidResponse() = runTest {
        val reader = makeReader(JsonPrimitive("not an object"))

        try {
            reader.changes("session-1")
            fail("Expected a ProtocolException")
        } catch (error: ProtocolException) {
            assertEquals("invalid_response", error.code)
        }
        assertEquals(listOf("/v2/sessions/session-1/changes"), calls.map { it.path })
    }

    @Test
    fun nonObjectProjectTextResponseThrowsInvalidResponse() = runTest {
        val reader = makeReader(JsonPrimitive(42))

        try {
            reader.file("session-1", "src/App.kt")
            fail("Expected a ProtocolException")
        } catch (error: ProtocolException) {
            assertEquals("invalid_response", error.code)
        }
        assertEquals(listOf("/v2/sessions/session-1/file"), calls.map { it.path })
        assertEquals(mapOf("path" to "src/App.kt"), calls.single().query)
    }

    @Test
    fun sessionIDIsPercentEncodedInTheRoute() = runTest {
        val reader = makeReader(jsonObjectOf())

        reader.changes("a/b c")

        assertEquals(listOf("/v2/sessions/a%2Fb%20c/changes"), calls.map { it.path })
    }

    @Test
    fun everyProjectRouteIsExact() = runTest {
        val reader = makeReader(jsonObjectOf())

        reader.changes("a/b c")
        reader.diff("a/b c", "src/App.kt")
        reader.file("a/b c", "src/App.kt")

        assertEquals(
            listOf(
                "/v2/sessions/a%2Fb%20c/changes",
                "/v2/sessions/a%2Fb%20c/diff",
                "/v2/sessions/a%2Fb%20c/file",
            ),
            calls.map { it.path },
        )
    }
}
