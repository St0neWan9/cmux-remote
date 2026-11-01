package com.cmuxremote.mobile.model

enum class SessionTrailing { Working, Locked, Resumable, None }

data class SessionItem(
    val id: String,
    val title: String,
    val agent: String,
    val age: String,
    val trailing: SessionTrailing = SessionTrailing.None,
    /** Workspace the conversation belongs to, used to group the list. */
    val workspaceKey: String = "",
    /** The Mac this conversation belongs to, for a list that shows several. */
    val hostKey: String? = null,
    /** Last activity, for the time sort. */
    val updatedAt: java.time.Instant? = null,
    /** Working directory, searchable like the iPhone list. */
    val cwd: String? = null,
    val writable: Boolean = false,
    val working: Boolean = false,
    val resumable: Boolean = false,
    /** The Mac's display name, shown in a flat list that mixes Macs. */
    val hostName: String? = null,
)
