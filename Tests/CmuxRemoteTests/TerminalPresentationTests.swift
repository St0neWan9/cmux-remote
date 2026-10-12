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

    @Test(arguments: [MobileTerminalRenderGridFrame.Screen.primary, .alternate])
    func smallerViewerKeepsComposerCursorAndFooterWithinItsOwnGrid(screen: MobileTerminalRenderGridFrame.Screen) throws {
        let workspace = UUID().uuidString, surface = UUID().uuidString
        let frame = try MobileTerminalRenderGridFrame(surfaceID: surface, stateSeq: 1, renderEpoch: "producer",
            columns: 104, rows: 26, cursor: .init(row: 23, column: 3),
            rowSpans: [.init(row: 0, column: 0, text: "header"), .init(row: 23, column: 0, text: "❯ draft"),
                .init(row: 25, column: 0, text: "footer")], activeScreen: screen)
        let payload: JSONValue = .object(["workspace_id": .string(workspace), "surface_id": .string(surface),
            "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
        var source = try TerminalSnapshotRenderer().render(payload, workspaceID: workspace, surfaceID: surface)
        source.allowsInput = true
        let fitted = try TerminalViewportPresentation().render(source, columns: 78, rows: 21)
        #expect(fitted.columns == 78 && fitted.rows == 21 && fitted.allowsInput)
        #expect(fitted.runtimeEpoch == source.runtimeEpoch)
        let cells = try #require(fitted.renderGrid)
        let decoded = try JSONDecoder().decode(MobileTerminalRenderGridFrame.self, from: JSONEncoder().encode(cells))
        #expect(decoded.rowSpans.map(\.text).joined().contains("❯ draft"))
        #expect(decoded.rowSpans.map(\.text).joined().contains("footer"))
        #expect(decoded.cursor?.row == 18 && decoded.cursor?.column == 3)
        #expect(decoded.rowSpans.allSatisfy { $0.row < 21 && $0.column + ($0.cellWidth ?? 1) <= 78 })
        #expect(frame.rows == 26 && frame.columns == 104 && frame.cursor?.row == 23)
        let expanded = try TerminalViewportPresentation().render(source, columns: 104, rows: 26)
        #expect(expanded.presentationKey != fitted.presentationKey)
        try expectPositionsWithinViewport(fitted.bytes, columns: 78, rows: 21)
    }

    @Test func horizontalViewportKeepsWholeWideGraphemesAndCursor() throws {
        let frame = try MobileTerminalRenderGridFrame(surfaceID: UUID().uuidString, stateSeq: 1, renderEpoch: "producer",
            columns: 12, rows: 2, cursor: .init(row: 0, column: 7),
            rowSpans: [.init(row: 0, column: 0, text: "abc中👩‍💻def", cellWidth: 10)])
        let fitted = MobileTerminalGridViewport().fit(frame, columns: 5, rows: 2)
        #expect(fitted.cursor?.column == 2)
        #expect(fitted.rowSpans.map(\.text).joined() == "👩‍💻def")
        #expect(fitted.rowSpans.allSatisfy { $0.column + ($0.cellWidth ?? 1) <= 5 })
        #expect(fitted.rowSpans.first?.cellWidth == 2)
    }

    private func expectPositionsWithinViewport(_ bytes: Data, columns: Int, rows: Int) throws {
        let text = String(decoding: bytes, as: UTF8.self)
        let expression = try NSRegularExpression(pattern: "\\u001B\\[(\\d+);(\\d+)H")
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let row = try #require(Int((text as NSString).substring(with: match.range(at: 1))))
            let column = try #require(Int((text as NSString).substring(with: match.range(at: 2))))
            #expect(row <= rows && column <= columns)
        }
    }
}
