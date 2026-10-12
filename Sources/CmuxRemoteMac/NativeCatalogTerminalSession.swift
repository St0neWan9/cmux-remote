import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Waits in an owned native pending row before attaching its existing remote producer.
public struct NativeCatalogTerminalSession: Sendable {
    private let owner: any CmuxControlling
    public init(owner: any CmuxControlling) { self.owner = owner }
    public func run(entryID: UUID, workspaceID: String, surfaceID: String) async throws {
        guard UUID(uuidString: workspaceID) != nil, UUID(uuidString: surfaceID) != nil else { throw BridgeError("terminal_required", "Run this pending entry inside its own cmux workspace.") }
        let params: [String: JSONValue] = ["entry_id": .string(entryID.uuidString)]
        while !Task.isCancelled {
            let ready = try await owner.request("mirror.catalog.wait", params: params)
            guard ready["ready"].bool == true else { continue }
            var open = params
            open["local_workspace_id"] = .string(workspaceID); open["local_surface_id"] = .string(surfaceID)
            let attached = try await owner.request("mirror.catalog.open", params: open)
            guard let raw = attached["projection_id"].string, let projection = UUID(uuidString: raw) else { throw BridgeError("invalid_response", "Invalid native attachment.") }
            try await TerminalViewer(owner: owner).run(projectionID: projection)
            return
        }
    }
}
