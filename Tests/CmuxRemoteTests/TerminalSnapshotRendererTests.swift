import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxTerminalReplay

@Suite struct TerminalSnapshotRendererTests {
    @Test(arguments: [MobileTerminalRenderGridFrame.Screen.primary, .alternate])
    func snapshotDoesNotPublishBeforeItsContentIsPainted(screen: MobileTerminalRenderGridFrame.Screen) throws {
        let workspace = UUID().uuidString, surface = UUID().uuidString
        let frame = try MobileTerminalRenderGridFrame(surfaceID: surface, stateSeq: 1, renderEpoch: "producer",
            columns: 80, rows: 24, rowSpans: [.init(row: 0, column: 0, styleID: 0, text: "STABLE_HEADER")], activeScreen: screen)
        let payload: JSONValue = .object(["workspace_id": .string(workspace), "surface_id": .string(surface),
            "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
        let replay = try TerminalSnapshotRenderer().render(payload, workspaceID: workspace, surfaceID: surface)
        // A terminal may present immediately when synchronized output ends,
        // even when the following paint was delivered in the same write.
        let publication = try #require(replay.bytes.range(of: Data("\u{1B}[?2026l".utf8)))
        let content = try #require(replay.bytes.range(of: Data("STABLE_HEADER".utf8)))
        #expect(content.upperBound <= publication.lowerBound, "The cleared intermediate screen must not become visible")
        #expect(publication.upperBound == replay.bytes.endIndex, "Only the completed snapshot may be published")
    }

    @Test(arguments: [MobileTerminalRenderGridFrame.Screen.primary, .alternate])
    func presentationDoesNotEnableLocalEventReports(screen: MobileTerminalRenderGridFrame.Screen) throws {
        let workspace = "11111111-1111-1111-1111-111111111111"
        let surface = "22222222-2222-2222-2222-222222222222"
        let eventModes = [9, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016]
        let frame = try MobileTerminalRenderGridFrame(surfaceID: surface, stateSeq: 1, renderEpoch: "producer",
            columns: 80, rows: 24, rowSpans: [.init(row: 0, column: 0, styleID: 0, text: "Source")],
            activeScreen: screen, modes: (eventModes + [1, 2004]).map { .init(code: $0, on: true) })
        let payload: JSONValue = .object(["workspace_id": .string(workspace), "surface_id": .string(surface),
            "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
        let replay = try TerminalSnapshotRenderer().render(payload, workspaceID: workspace, surfaceID: surface)
        let output = String(decoding: replay.bytes, as: UTF8.self)
        for mode in eventModes {
            #expect(!output.contains("\u{1B}[?\(mode)h"), "Local event mode \(mode) must stay disabled")
            #expect(output.contains("\u{1B}[?\(mode)l"))
        }
        #expect(output.contains("Source"))
        #expect(output.contains("\u{1B}[?1h"))
        #expect(output.contains("\u{1B}[?2004h"))
    }
}
