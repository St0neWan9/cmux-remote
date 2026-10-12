import Foundation
import CryptoKit
import CmuxRemoteCore
import CmuxTerminalReplay

/// Validates full character-grid replays before producing terminal presentation bytes.
public struct TerminalSnapshotRenderer: Sendable {
    public init() {}
    public func render(_ payload: JSONValue, workspaceID: String, surfaceID: String) throws -> MirrorTerminalSnapshot {
        guard payload["workspace_id"].string?.lowercased() == workspaceID.lowercased(),
              payload["surface_id"].string?.lowercased() == surfaceID.lowercased(), payload["render_grid"].object != nil else {
            throw BridgeError("mirror_unsupported", "This cmux version did not return a matching character-grid replay.", status: 422)
        }
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload["render_grid"]))
        guard let object = raw as? [String: Any] else { throw BridgeError("invalid_response", "Invalid terminal replay.", status: 502) }
        var frame = try MobileTerminalRenderGridFrame.decodeJSONObject(object)
        guard frame.full, frame.surfaceID.lowercased() == surfaceID.lowercased(), !frame.renderEpoch.isEmpty,
              frame.columns > 0, frame.columns <= 1000, frame.rows > 0, frame.rows <= 500,
              frame.scrollbackRows <= 4000 else { throw BridgeError("mirror_unsupported", "Terminal replay dimensions or runtime identity are unsupported.", status: 422) }
        // Cell text cannot inject terminal control sequences, including clipboard OSCs.
        guard (frame.rowSpans + frame.scrollbackSpans).allSatisfy({ span in
            !span.text.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
        }) else { throw BridgeError("invalid_response", "Terminal cell text contains control characters.", status: 502) }
        // A desktop snapshot viewer must not manufacture focus/mouse input on
        // behalf of the producer. Its coordinates and focus are local only.
        // The upstream full replay resets these modes before restoring modes.
        frame.modes.removeAll { !$0.ansi && [9, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016].contains($0.code) }
        let bytes = TerminalPresentationFrame().bytes(for: presentationBytes(frame))
        guard bytes.count <= 4_194_304 else { throw BridgeError("too_large", "Terminal replay exceeds the transfer limit.", status: 413) }
        var snapshot = MirrorTerminalSnapshot(workspaceID: workspaceID.lowercased(), surfaceID: surfaceID.lowercased(), runtimeEpoch: frame.renderEpoch,
                                      columns: frame.columns, rows: frame.rows, bytes: bytes)
        if frame.scrollbackRows == 0 {
            var baseline = frame
            baseline.rowSpans = []; baseline.cursor = nil; baseline.clearedRows = []
            var identity = MobileTerminalRenderGridReplay(baseline).patchBytes()
            identity.append(Data("\(frame.renderEpoch):\(frame.columns):\(frame.rows):\(frame.activeScreen)".utf8))
            snapshot.presentationKey = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
            var paint = frame
            paint.full = false; paint.clearedRows = Array(0..<frame.rows)
            paint.scrolledRows = 0; paint.scrollbackRows = 0; paint.scrollbackSpans = []
            snapshot.repaintBytes = TerminalPresentationFrame().bytes(for: MobileTerminalRenderGridReplay(paint).patchBytes())
        }
        guard bytes.count + (snapshot.repaintBytes?.count ?? 0) <= 4_194_304 else {
            throw BridgeError("too_large", "Terminal presentation exceeds the transfer limit.", status: 413)
        }
        return snapshot
    }
    private func presentationBytes(_ frame: MobileTerminalRenderGridFrame) -> Data {
        guard frame.activeScreen == .alternate else { return MobileTerminalRenderGridReplay(frame).patchBytes() }
        // The mobile full replay flows every producer row. A smaller ordinary
        // terminal scrolls the TUI's header away. Install its modes/theme with
        // an empty one-row baseline, then paint the captured grid by position.
        // This clips to the viewer without resizing or mutating the producer.
        var baseline = frame
        baseline.rows = 1; baseline.cursor = nil; baseline.rowSpans = []; baseline.clearedRows = []
        baseline.scrollbackRows = 0; baseline.scrollbackSpans = []; baseline.scrolledRows = 0
        var paint = frame
        paint.full = false; paint.clearedRows = Array(0..<frame.rows)
        paint.scrolledRows = 0; paint.scrollbackRows = 0; paint.scrollbackSpans = []
        var bytes = MobileTerminalRenderGridReplay(baseline).patchBytes()
        bytes.append(MobileTerminalRenderGridReplay(paint).patchBytes())
        return bytes
    }
}
