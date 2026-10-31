package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The transcript decoder must keep every field a detail surface renders, and never drop an unknown row. */
class BridgeDecodeTest {
    private fun decode(json: String) = BridgeRepository.decodeMessage(Json.parse(json))

    @Test
    fun decodesAToolUsesInputOutputAndReferences() {
        val message = decode(
            """
            {"id":"m1","seq":7,"role":"agent","kind":{
              "type":"tool_use","tool_name":"Read","summary":"Read a.swift",
              "input_detail":"path: a.swift","output":"file body","status":"succeeded",
              "referenced_paths":["src/a.swift","src/b.swift"]}}
            """.trimIndent(),
        )
        assertNotNull(message)
        assertEquals("tool_use", message!!.kind)
        assertEquals("Read", message.toolName)
        assertEquals("path: a.swift", message.inputDetail)
        assertEquals("file body", message.output)
        assertEquals(listOf("src/a.swift", "src/b.swift"), message.references)
        assertEquals("succeeded", message.status)
    }

    @Test
    fun decodesATerminalCapturesCommandExitCodeAndDuration() {
        val message = decode(
            """
            {"id":"m2","seq":8,"role":"agent","kind":{
              "type":"terminal","command":"swift build","summary":"Build",
              "output":"built","exit_code":2,"duration_seconds":1.5,"is_running":false}}
            """.trimIndent(),
        )
        assertEquals("swift build", message!!.command)
        assertEquals("built", message.output)
        assertEquals(2, message.exitCode)
        assertEquals(1.5, message.durationSeconds!!, 0.0001)
    }

    @Test
    fun decodesAQuestionAndItsOptions() {
        val message = decode(
            """
            {"id":"m3","seq":9,"role":"agent","kind":{
              "type":"question","prompt":"Which one?","options":["a","b"],
              "selected_option_label":"b"}}
            """.trimIndent(),
        )
        assertEquals("Which one?", message!!.prompt)
        assertEquals(listOf("a", "b"), message.options)
        assertEquals("b", message.selectedOption)
    }

    @Test
    fun anUnknownKindStillShowsItsText() {
        val message = decode(
            """{"id":"m4","seq":10,"role":"agent","kind":{"type":"something_new","text":"kept"}}""",
        )
        assertEquals("something_new", message!!.kind)
        assertEquals("kept", message.text)
    }

    @Test
    fun readsTheSessionListBackgroundSyncStored() {
        val sessions = BridgeRepository.decodeSessions(
            """
            [{"id":"s1","agent":"claude","title":"Build","workspaceID":"w","surfaceID":"p",
              "state":"working","updatedAt":"2026-10-31T10:00:00Z","resumable":false}]
            """.trimIndent(),
        )
        assertEquals(1, sessions.size)
        assertEquals("s1", sessions[0].id)
        assertTrue(sessions[0].working)
        assertTrue(sessions[0].writable)
    }

    @Test
    fun aMalformedCacheIsAnEmptyListNotACrash() {
        assertEquals(emptyList<SessionDescriptor>(), BridgeRepository.decodeSessions("not json"))
    }

    @Test
    fun aRowWithoutAnIdIsDropped() {
        assertEquals(null, decode("""{"seq":1,"kind":{"type":"prose","text":"x"}}"""))
        assertTrue(true)
    }
}
