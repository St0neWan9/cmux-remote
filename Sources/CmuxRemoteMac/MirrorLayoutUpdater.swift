import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Rearranges only owned local viewers, preserving their process and surface IDs.
struct MirrorLayoutUpdater: Sendable {
    let local: any CmuxControlling
    /// Native creation can return before the read snapshot publishes the new tab.
    /// Re-read only that confirmed creation; never repeat a mutation or ignore foreign tabs.
    func awaitCreatedSurface(_ id: String, workspace: String, owned: Set<String>) async throws {
        for attempt in 0..<8 {
            try Task.checkCancellation()
            do { _ = try await members(workspace: workspace, owned: owned); return }
            catch let error as BridgeError where error.code == "mirror_local_changed" && attempt < 7 {
                let value = try await local.request("surface.list", params: ["workspace_id": .string(workspace)])
                guard value["workspace_id"].string == workspace, let rows = value["surfaces"].array else { throw error }
                let observed = Set(rows.compactMap { $0["id"].string })
                guard rows.count == observed.count, observed == owned.subtracting([id]) || observed == owned else { throw error }
                if observed == owned { return }
            }
        }
    }
    func members(workspace: String, owned: Set<String>) async throws -> [String: String] {
        let result = try await observedMembers(workspace: workspace)
        guard Set(result.keys) == owned else {
            let missing = owned.subtracting(result.keys).sorted().joined(separator: ",")
            let extra = Set(result.keys).subtracting(owned).sorted().joined(separator: ",")
            throw BridgeError("mirror_local_changed", "Local mirror membership mismatch: expected \(owned.count), observed \(result.count); missing [\(missing)]; extra [\(extra)].", status: 409)
        }
        return result
    }
    func observedMembers(workspace: String) async throws -> [String: String] {
        let value = try await local.request("surface.list", params: ["workspace_id": .string(workspace)])
        guard value["workspace_id"].string == workspace, let rows = value["surfaces"].array, rows.count <= 128 else { throw BridgeError("invalid_response", "Invalid local mirror membership.") }
        var result: [String: String] = [:]
        for row in rows {
            guard let id = row["id"].string, let pane = row["pane_id"].string,
                  UUID(uuidString: id) != nil, UUID(uuidString: pane) != nil, result[id] == nil else {
                throw BridgeError("invalid_response", "Invalid local mirror surface.")
            }
            result[id] = pane
        }
        return result
    }
    func apply(_ plan: MirrorLayoutPlan, workspace: String, mapping: [String: String],
               admit: @Sendable () async throws -> Void) async throws {
        let owned = Set(mapping.values)
        let seed = mapping[plan.firstSurface.id]!
        let initial = try await members(workspace: workspace, owned: owned)
        let rootPane = initial[seed]!
        // Gather existing viewers into one pane, then split existing tabs out.
        // Moving a view never restarts it or sends anything to its producer.
        for id in mapping.values.sorted() where id != seed {
            try await move(id, to: rootPane, workspace: workspace, owned: owned, admit: admit)
        }
        try await place(plan, workspace: workspace, mapping: mapping, owned: owned, admit: admit)
    }
    private func move(_ id: String, to pane: String, workspace: String, owned: Set<String>,
                      admit: @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation(); try await admit()
        let membership = try await members(workspace: workspace, owned: owned)
        guard membership[id] != pane else { return }
        _ = try await local.request("surface.move", params: ["workspace_id": .string(workspace), "surface_id": .string(id),
            "pane_id": .string(pane), "focus": .bool(false)])
    }
    private func place(_ plan: MirrorLayoutPlan, workspace: String, mapping: [String: String], owned: Set<String>,
                       admit: @Sendable () async throws -> Void) async throws {
        switch plan {
        case .pane(let terminals):
            for (index, terminal) in terminals.enumerated() {
                try Task.checkCancellation(); try await admit()
                _ = try await members(workspace: workspace, owned: owned)
                _ = try await local.request("surface.reorder", params: ["workspace_id": .string(workspace),
                    "surface_id": .string(mapping[terminal.id]!), "index": .number(Double(index)), "focus": .bool(false)])
            }
        case .split(let direction, let first, let second):
            try Task.checkCancellation(); try await admit()
            _ = try await members(workspace: workspace, owned: owned)
            let lead = mapping[second.firstSurface.id]!
            let value = try await local.request("surface.split_off", params: ["workspace_id": .string(workspace),
                "surface_id": .string(lead), "direction": .string(direction), "focus": .bool(false)])
            guard value["surface_id"].string == lead, let pane = value["pane_id"].string, UUID(uuidString: pane) != nil else {
                throw BridgeError("outcome_unknown", "Inspect the local layout before repeating the split.", status: 409)
            }
            for surface in second.surfaces.dropFirst() {
                try await move(mapping[surface.id]!, to: pane, workspace: workspace, owned: owned, admit: admit)
            }
            try await place(first, workspace: workspace, mapping: mapping, owned: owned, admit: admit)
            try await place(second, workspace: workspace, mapping: mapping, owned: owned, admit: admit)
        }
    }
}
