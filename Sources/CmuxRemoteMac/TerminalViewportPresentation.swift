import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Adapts optional source cells to a viewer's own grid while retaining input authority.
struct TerminalViewportPresentation: Sendable {
    func render(_ snapshot: MirrorTerminalSnapshot, columns: Int, rows: Int, topRow: Int? = nil) throws -> MirrorTerminalSnapshot {
        guard let cells = snapshot.renderGrid else { return snapshot }
        let payload: JSONValue = .object(["workspace_id": .string(snapshot.workspaceID),
            "surface_id": .string(snapshot.surfaceID), "render_grid": cells])
        var result = try TerminalSnapshotRenderer().render(payload, workspaceID: snapshot.workspaceID,
            surfaceID: snapshot.surfaceID, viewportColumns: min(columns, 1000), viewportRows: min(rows, 500), viewportTopRow: topRow)
        guard result.runtimeEpoch == snapshot.runtimeEpoch else { throw BridgeError("invalid_response", "Viewport cells belong to another producer.") }
        result.allowsInput = snapshot.allowsInput
        result.pasteSupported = snapshot.pasteSupported
        return result
    }
}
