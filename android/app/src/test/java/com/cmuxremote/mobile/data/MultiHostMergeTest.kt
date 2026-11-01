package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure merge helpers mirroring how remote sessions and workspaces are tagged with their
 * host before being flattened into one list or map.
 */
class MultiHostMergeTest {
    private fun merge(hosts: List<Pair<String, List<String>>>): List<String> =
        hosts.flatMap { (host, sessions) -> sessions.map { session -> "$host/$session" } }

    private fun mergeWorkspaces(hosts: List<Pair<String, List<String>>>): Map<String, List<String>> =
        hosts.flatMap { (host, ids) -> ids.map { id -> id to host } }
            .groupBy({ it.first }, { it.second })

    @Test
    fun sessionsKeepHostOrderThenRemoteOrder() {
        val hosts = listOf(
            "alpha" to listOf("build", "deploy"),
            "beta" to listOf("review", "test"),
        )

        assertEquals(
            listOf("alpha/build", "alpha/deploy", "beta/review", "beta/test"),
            merge(hosts),
        )
    }

    @Test
    fun duplicateNamesFromDifferentHostsStaySeparate() {
        val merged = merge(
            listOf(
                "alpha" to listOf("main", "shared"),
                "beta" to listOf("shared", "main"),
            ),
        )

        assertEquals(listOf("alpha/main", "alpha/shared", "beta/shared", "beta/main"), merged)
        assertEquals(4, merged.distinct().size)
        assertEquals(2, merged.count { it.endsWith("/main") })
    }

    @Test
    fun workspaceMapKeepsIdsFromBothHosts() {
        val merged = mergeWorkspaces(
            listOf(
                "alpha" to listOf("ws-1", "ws-2"),
                "beta" to listOf("ws-3"),
            ),
        )

        assertEquals(setOf("ws-1", "ws-2", "ws-3"), merged.keys)
        assertEquals(listOf("alpha"), merged.getValue("ws-1"))
        assertEquals(listOf("alpha"), merged.getValue("ws-2"))
        assertEquals(listOf("beta"), merged.getValue("ws-3"))
    }

    @Test
    fun workspaceIdClaimedByBothHostsKeepsBothHosts() {
        val merged = mergeWorkspaces(
            listOf(
                "alpha" to listOf("ws-1"),
                "beta" to listOf("ws-1"),
            ),
        )

        assertEquals(1, merged.size)
        assertEquals(listOf("alpha", "beta"), merged.getValue("ws-1"))
    }
}
