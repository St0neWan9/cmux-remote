package com.cmuxremote.mobile.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Which fixed decision modes the Mac can actually deliver.
 *
 * A mode that cannot be delivered never becomes a button: the Mac's own
 * `available_modes` wins, and the permission fallback mirrors the iPhone's
 * policy for Claude and Codex.
 */
object FeedDecisionPolicy {
    private val permissionModes = listOf("once", "always", "all", "bypass", "deny")
    private val planModes = listOf("ultraplan", "bypassPermissions", "autoAccept", "manual", "deny")

    fun permissionModes(item: FeedItem): List<String> {
        item.availableModes?.let { available -> return permissionModes.filter { it in available } }
        val source = item.source?.lowercase().orEmpty()
        if (source.isNotEmpty() && source != "claude" && source != "codex") return listOf("once", "deny")
        // This companion does not support Claude's bypass mode.
        if (source == "claude") return permissionModes.filter { it != "bypass" }
        if (source == "codex") {
            val raw = item.toolInputCapabilities ?: item.toolInput
            val caps = raw?.let {
                runCatching { com.cmuxremote.mobile.protocol.Json.parse(it) as? JsonObject }.getOrNull()
            } ?: return permissionModes.filter { it != "bypass" }
            val method = (caps["app_server_method"] as? JsonPrimitive)?.content
            if (method == "item/permissions/requestApproval") return permissionModes.filter { it != "bypass" }
            val decisions = caps["available_decisions"] as? JsonArray
                ?: caps["availableDecisions"] as? JsonArray
            fun supports(name: String) = decisions == null || decisions.any { row ->
                when (row) {
                    is JsonPrimitive -> row.content == name
                    is JsonObject -> row.containsKey(name)
                    else -> false
                }
            }
            val amendment = caps["proposed_execpolicy_amendment"] != null &&
                caps["proposed_execpolicy_amendment"]?.toString() != "null"
            val network = (caps["proposed_network_policy_amendments"] as? JsonArray)?.isNotEmpty() == true
            val allowAll = method == "item/commandExecution/requestApproval" &&
                (amendment || network) && supports("acceptWithExecpolicyAmendment")
            return buildList {
                if (supports("accept")) add("once")
                if (supports("acceptForSession")) add("always")
                if (allowAll) add("all")
                add("deny")
            }.ifEmpty { listOf("deny") }
        }
        return permissionModes
    }

    fun planModes(item: FeedItem): List<String> {
        val available = item.availableModes ?: return planModes
        return planModes.filter { it in available }
    }
}
