import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Uses native groups and row rendering; it never installs a replacement sidebar.
public actor NativeRemoteWorkspaceGroup: NativeRemoteWorkspaceGrouping {
    private let local: any CmuxControlling
    private let identity: String
    private let name: String
    private var tail: Task<Void, any Error>?
    private var pending = 0
    /// Creates the native group owner with an injected local cmux transport.
    public init(local: any CmuxControlling, identity: String = "cmux-remote.native.remote", name: String = "Remote") {
        self.local = local; self.identity = identity; self.name = name
    }
    /// Serializes a bounded number of group mutations without changing focus.
    public func place(workspaceID: String, windowID: String?) async throws {
        guard UUID(uuidString: workspaceID) != nil, windowID == nil || UUID(uuidString: windowID!) != nil else {
            throw BridgeError("invalid_input", "Use the newly created local workspace identity.")
        }
        guard pending < 64 else { throw BridgeError("mirror_busy", "Native grouping is busy.", status: 429) }
        pending += 1; defer { pending -= 1 }
        let prior = tail
        let operation = Task {
            _ = try? await prior?.value
            try Task.checkCancellation()
            try await self.perform(workspaceID: workspaceID, windowID: windowID)
        }
        tail = operation
        try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }
    private func perform(workspaceID: String, windowID: String?) async throws {
        var scope: [String: JSONValue] = [:]
        if let windowID { scope["window_id"] = .string(windowID) }
        else { scope["workspace_id"] = .string(workspaceID) }
        let listing: JSONValue
        do { listing = try await local.request("workspace.group.list", params: scope) }
        catch let error as BridgeError where error.code == "method_not_found" {
            throw BridgeError("native_group_unsupported", "This cmux version does not support native workspace groups.", status: 422)
        }
        guard let groups = listing["groups"].array, groups.count <= 4096,
              let resolvedWindow = listing["window_id"].string, UUID(uuidString: resolvedWindow) != nil,
              windowID == nil || resolvedWindow == windowID else { throw BridgeError("invalid_response", "Invalid native group window.") }
        scope = ["window_id": .string(resolvedWindow)]
        let before = try await local.request("workspace.list", params: scope)
        guard (before["workspaces"].array ?? []).contains(where: { $0["id"].string == workspaceID }) else { throw BridgeError("stale_binding", "The local mirror moved or closed.", status: 409) }
        var group = groups.first { $0["external_id"].string == identity }
        if group == nil {
            var params = scope
            // Remote is the user-requested group name, not copied cmux UI.
            params["name"] = .string(name); params["external_id"] = .string(identity); params["child_workspace_ids"] = .array([])
            let created = try await local.request("workspace.group.create", params: params)
            group = created["group"]
        }
        guard let group, group["external_id"].string == identity, let id = group["id"].string, UUID(uuidString: id) != nil else {
            throw BridgeError("native_group_unsupported", "Native group identity was not preserved.", status: 422)
        }
        if !(group["member_workspace_ids"].array ?? []).contains(.string(workspaceID)) {
            var params = scope
            params["group_id"] = .string(id); params["workspace_id"] = .string(workspaceID); params["placement"] = .string("end")
            try Task.checkCancellation(); _ = try await local.request("workspace.group.add", params: params)
        }
        let updated = try await local.request("workspace.group.list", params: scope)
        guard let owned = updated["groups"].array?.first(where: { $0["id"].string == id && $0["external_id"].string == identity }),
              let members = owned["member_workspace_ids"].array?.compactMap(\.string), members.contains(workspaceID),
              let anchor = owned["anchor_workspace_id"].string, members.contains(anchor) else { throw BridgeError("outcome_unknown", "Inspect the native group before repeating placement.", status: 409) }
        let current = try await local.request("workspace.list", params: scope)
        guard let rows = current["workspaces"].array, rows.count <= 4096 else { throw BridgeError("invalid_response", "Invalid native workspace order.") }
        let order = rows.compactMap { $0["id"].string }
        guard order.count == rows.count, Set(order).count == order.count, Set(members).isSubset(of: Set(order)) else { throw BridgeError("stale_binding", "The native group changed during placement.", status: 409) }
        let memberSet = Set(members)
        let desired = order.filter { !memberSet.contains($0) } + [anchor] + members.filter { $0 != anchor }
        if order != desired {
            var params = scope; params["workspace_ids"] = .array(desired.map(JSONValue.string))
            // Moving just the anchor is clamped inside its group. Move the
            // complete owned block, retaining every other workspace's order.
            try Task.checkCancellation(); _ = try await local.request("workspace.reorder_many", params: params)
        }
    }
}
