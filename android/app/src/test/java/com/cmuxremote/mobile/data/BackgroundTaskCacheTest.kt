package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The task cache is a convenience: bounded, owner-scoped, and never the authority. */
class BackgroundTaskCacheTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun cache() = BackgroundTaskCache(folder.newFolder())

    private fun entry(text: String, next: Int? = null) = BackgroundTaskCache.Entry(
        tool = "Bash",
        summary = "swift build",
        running = false,
        text = text,
        nextOffset = next,
        storedAt = System.currentTimeMillis(),
    )

    @Test
    fun aSavedPageLoadsBack() {
        val cache = cache()
        cache.save(entry("built", next = 8192), "scope", "session", "task")
        val loaded = cache.load("scope", "session", "task")
        assertNotNull(loaded)
        assertEquals("built", loaded!!.text)
        assertEquals(8192, loaded.nextOffset)
        assertEquals("Bash", loaded.tool)
    }

    @Test
    fun anotherScopeOrTaskDoesNotSeeIt() {
        val cache = cache()
        cache.save(entry("built"), "scope", "session", "task")
        assertNull(cache.load("other", "session", "task"))
        assertNull(cache.load("scope", "session", "other"))
    }

    @Test
    fun readingIsAUseAndMovesTheCopyToTheEnd() {
        val cache = cache()
        cache.save(entry("a"), "scope", "s", "a")
        val before = onlyFileTime()
        Thread.sleep(50)
        assertNotNull(cache.load("scope", "s", "a"))
        val after = onlyFileTime()
        assertTrue(after > before)
    }

    @Test
    fun anOversizedPageIsNotStored() {
        val cache = cache()
        cache.save(entry("x".repeat(4_200_000)), "scope", "session", "task")
        assertNull(cache.load("scope", "session", "task"))
        assertEquals(0, cache.entryCount())
    }

    @Test
    fun onlySixteenTasksAreKeptAndTheOldestGoesFirst() {
        val cache = cache()
        for (index in 0 until 17) {
            cache.save(entry("page $index"), "scope", "session", "task-$index")
            Thread.sleep(10)
        }
        assertEquals(16, cache.entryCount())
        assertNull(cache.load("scope", "session", "task-0"))
        assertNotNull(cache.load("scope", "session", "task-1"))
        assertNotNull(cache.load("scope", "session", "task-16"))
    }

    @Test
    fun removingAHostRemovesOnlyItsTasks() {
        val cache = cache()
        cache.save(entry("a"), "host-a:device", "s", "t")
        cache.save(entry("b"), "host-b:device", "s", "t")
        cache.remove("host-a:device")
        assertNull(cache.load("host-a:device", "s", "t"))
        assertNotNull(cache.load("host-b:device", "s", "t"))
    }

    /** The cache hashes names; with one saved entry the only file is that entry. */
    private fun onlyFileTime(): Long {
        val directory = folder.root.listFiles()?.firstOrNull { it.isDirectory } ?: return 0L
        return directory.listFiles()?.filter { it.name.endsWith(".json") }?.single()?.lastModified() ?: 0L
    }
}
