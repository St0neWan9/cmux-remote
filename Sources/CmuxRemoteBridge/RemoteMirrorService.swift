import Foundation
import CryptoKit
import CmuxRemoteCore

/// Fixed terminal-mirror operations over the owner's local cmux authority.
public actor RemoteMirrorService {
    private let cmux: any CmuxControlling
    private let renderer = TerminalSnapshotRenderer()
    private let mutations: MutationLedger
    public init(cmux: any CmuxControlling, mutations: MutationLedger? = nil) { self.cmux = cmux; self.mutations = mutations ?? MutationLedger() }

    public func workspace(id: String) async throws -> MirrorWorkspaceSnapshot {
        try validate(id)
        let tree = try await cmux.request("system.tree", params: ["all": .bool(true)])
        let workspaces = (tree["windows"].array ?? []).flatMap { $0["workspaces"].array ?? [] } + (tree["workspaces"].array ?? [])
        guard let workspace = workspaces.first(where: { $0["id"].string?.lowercased() == id.lowercased() }) else {
            throw BridgeError("not_found", "The remote workspace no longer exists.", status: 404)
        }
        var surfaces: [MirrorSurface] = []
        for pane in workspace["panes"].array ?? [] {
            guard let paneID = pane["id"].string, UUID(uuidString: paneID) != nil else { continue }
            for surface in pane["surfaces"].array ?? [] where surface["type"].string == "terminal" {
                guard let surfaceID = surface["id"].string, UUID(uuidString: surfaceID) != nil else { continue }
                surfaces.append(MirrorSurface(id: surfaceID.lowercased(), paneID: paneID.lowercased(), title: surface["title"].string ?? ""))
            }
        }
        guard !surfaces.isEmpty, surfaces.count <= 64 else { throw BridgeError("mirror_unsupported", "Choose a workspace with between one and 64 terminals.", status: 422) }
        return MirrorWorkspaceSnapshot(id: id.lowercased(), title: workspace["title"].string ?? "", layout: workspace["layout"], surfaces: surfaces)
    }

    public func replay(workspaceID: String, surfaceID: String) async throws -> MirrorTerminalSnapshot {
        try await requireSurface(workspaceID: workspaceID, surfaceID: surfaceID)
        // terminal.replay can wake hibernated agents. A read grant must not launch one.
        let state = try await cmux.request("surface.input_state", params: ["workspace_id": .string(workspaceID), "surface_id": .string(surfaceID)])
        guard state["terminal"].bool == true, state["lifecycle"].string != "hibernated" else {
            throw BridgeError("mirror_unsupported", "Only an existing running terminal can be mirrored; wake it explicitly on the host first.", status: 422)
        }
        let value = try await cmux.request("terminal.replay", params: ["workspace_id": .string(workspaceID), "surface_id": .string(surfaceID),
            "anchor": .string("screen"), "max_scrollback_rows": .number(0)])
        return try renderer.render(value, workspaceID: workspaceID, surfaceID: surfaceID)
    }

    public func input(workspaceID: String, surfaceID: String, clientID: String, request: MirrorInputRequest,
                      authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt {
        guard !request.text.isEmpty, request.text.utf8.count <= 16_384, !request.runtimeEpoch.isEmpty else {
            throw BridgeError("invalid_input", "Terminal input must be bounded and belong to an observed runtime.")
        }
        let signature = try MutationLedger.fingerprint(action: "terminal.input", resource: workspaceID.lowercased() + ":" + surfaceID.lowercased(),
                                                       payload: .object(["epoch": .string(request.runtimeEpoch), "text": .string(request.text)]))
        if let prior = try await mutations.prior(clientID: clientID, operationID: request.operationID, fingerprint: signature) {
            try await authorize(); return try priorReceipt(prior)
        }
        let snapshot = try await replay(workspaceID: workspaceID, surfaceID: surfaceID)
        guard snapshot.runtimeEpoch == request.runtimeEpoch else { throw BridgeError("stale_binding", "The remote terminal runtime changed. Reattach before sending input.", status: 409) }
        try await authorize()
        // Recheck after actor suspension so simultaneous duplicates cannot both type.
        if let prior = try await mutations.begin(clientID: clientID, operationID: request.operationID, fingerprint: signature,
                                                workspaceID: workspaceID, capability: .terminalInput) {
            try await authorize(); return try priorReceipt(prior)
        }
        try await authorize()
        // Ledger and authorization hops can outlive the producer observed above.
        // Re-read the exact membership/lifecycle/epoch before delivery, then recheck scope.
        let current = try await replay(workspaceID: workspaceID, surfaceID: surfaceID)
        guard current.runtimeEpoch == request.runtimeEpoch else { throw BridgeError("stale_binding", "The remote terminal changed during authorization. Reattach before sending input.", status: 409) }
        try await authorize()
        do {
            let result = try await cmux.request("mobile.terminal.input", params: ["workspace_id": .string(workspaceID), "surface_id": .string(surfaceID), "text": .string(request.text)])
            guard result["accepted"].bool != false else { throw BridgeError("outcome_unknown", "Inspect the remote terminal before repeating input.", status: 409) }
            return try await mutations.complete(clientID: clientID, operationID: request.operationID)
        } catch { throw BridgeError("outcome_unknown", "Terminal input outcome is unknown; it was not retried.", status: 409) }
    }

    private func requireSurface(workspaceID: String, surfaceID: String) async throws {
        try validate(workspaceID); try validate(surfaceID)
        let result = try await cmux.request("surface.list", params: ["workspace_id": .string(workspaceID)])
        guard result["workspace_id"].string?.lowercased() == workspaceID.lowercased(),
              (result["surfaces"].array ?? []).contains(where: { $0["id"].string?.lowercased() == surfaceID.lowercased() && $0["type"].string == "terminal" }) else {
            throw BridgeError("stale_binding", "The terminal does not belong to this workspace.", status: 409)
        }
    }
    private func validate(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw BridgeError("invalid_input", "Use an explicit workspace or surface UUID.") }
    }
    private func priorReceipt(_ prior: MutationLedger.Entry) throws -> MutationReceipt {
        guard let receipt = prior.receipt else { throw BridgeError("outcome_unknown", "The previous input outcome is unknown; it was not retried.", status: 409) }
        return receipt
    }
}
