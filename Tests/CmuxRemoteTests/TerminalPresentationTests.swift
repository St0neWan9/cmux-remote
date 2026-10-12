import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxTerminalReplay
@testable import CmuxRemoteMac

@Suite struct TerminalPresentationTests {
    @Test(arguments: [MobileTerminalRenderGridFrame.Screen.primary, .alternate])
    func consecutiveFramesKeepTheMountedScreen(screen: MobileTerminalRenderGridFrame.Screen) throws {
        let workspace = UUID().uuidString, surface = UUID().uuidString
        func snapshot(_ text: String, columns: Int = 80, mode: Int = 1) throws -> MirrorTerminalSnapshot {
            let frame = try MobileTerminalRenderGridFrame(surfaceID: surface, stateSeq: 1, renderEpoch: "producer",
                columns: columns, rows: 24, rowSpans: [.init(row: 0, column: 0, styleID: 0, text: text)],
                activeScreen: screen, modes: [.init(code: mode, on: true)])
            let payload: JSONValue = .object(["workspace_id": .string(workspace), "surface_id": .string(surface),
                "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
            return try TerminalSnapshotRenderer().render(payload, workspaceID: workspace, surfaceID: surface)
        }
        var sequence = TerminalPresentationSequence()
        let first = try snapshot("first"), second = try snapshot("second")
        #expect(sequence.next(first) == first.bytes)
        #expect(first.presentationKey == second.presentationKey)
        let update = sequence.next(second)
        #expect(update == second.repaintBytes)
        #expect(String(decoding: update, as: UTF8.self).contains("second"))
        #expect(!String(decoding: update, as: UTF8.self).contains("\u{1B}[?1049"), "Ongoing paint must not switch or clear screens")
        let resized = try snapshot("resized", columns: 100)
        #expect(sequence.next(resized) == resized.bytes)
        let changedModes = try snapshot("new modes", columns: 100, mode: 2004)
        #expect(sequence.next(changedModes) == changedModes.bytes)
    }

    @Test func legacyAndFreshViewersAlwaysStartWithFullRestore() throws {
        var snapshot = MirrorTerminalSnapshot(workspaceID: UUID().uuidString, surfaceID: UUID().uuidString,
            runtimeEpoch: "producer", columns: 80, rows: 24, bytes: Data("full".utf8))
        var first = TerminalPresentationSequence()
        #expect(first.next(snapshot) == snapshot.bytes)
        #expect(first.next(snapshot) == snapshot.bytes)
        snapshot.presentationKey = "key"; snapshot.repaintBytes = Data("repaint".utf8)
        #expect(first.next(snapshot) == snapshot.bytes)
        #expect(first.next(snapshot) == snapshot.repaintBytes)
        var second = TerminalPresentationSequence()
        #expect(second.next(snapshot) == snapshot.bytes)
        snapshot.presentationKey = "new epoch"
        #expect(first.next(snapshot) == snapshot.bytes)
    }
}
