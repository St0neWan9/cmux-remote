import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxTerminalReplay
@testable import CmuxRemoteMac

@Suite struct TerminalPointerInputTests {
    @Test func bracketedPastePreservesLiteralPointerSequencesAcrossFragments() throws {
        let contents = Data("literal \u{1B}[<64;12;9M".utf8)
        let paste = Data("\u{1B}[200~literal \u{1B}[<64;12;9M\u{1B}[201~".utf8)
        var decoder = TerminalPointerInputDecoder(), output = Data()
        for byte in paste {
            for event in try decoder.consume(Data([byte])) {
                if case .paste(let bytes) = event { output.append(bytes) }
                else { Issue.record("Paste must not become scrolling or keyboard escapes") }
            }
        }
        #expect(output == contents)
    }
    @Test func wheelAndClicksNeverBecomeRemoteKeyboardInput() throws {
        var decoder = TerminalPointerInputDecoder()
        let events = try decoder.consume(Data("你好\u{1B}[A\u{1B}[<64;12;9M\u{1B}[<0;12;9M\u{1B}[<0;12;9m\u{1B}[<65;12;9M!".utf8))
        var keyboard = Data(), scrolling: [Int] = []
        for event in events {
            switch event { case .keyboard(let data): keyboard.append(data); case .scroll(let delta): scrolling.append(delta); case .paste: Issue.record("Unexpected paste") }
        }
        #expect(keyboard == Data("你好\u{1B}[A!".utf8))
        #expect(scrolling == [-3, 3])
    }
    @Test func pointerReportsSurviveEveryPacketBoundary() throws {
        let report = Data("\u{1B}[<64;12;9M".utf8)
        for split in 0...report.count {
            var decoder = TerminalPointerInputDecoder()
            let events = try decoder.consume(Data(report.prefix(split))) + decoder.consume(Data(report.dropFirst(split)))
            #expect(events.count == 1)
            if case .scroll(let amount) = events.first { #expect(amount == -3) }
            else { Issue.record("Mouse report leaked into keyboard input") }
        }
    }
    @Test func escapeIsPreservedButIncompleteOrOversizedPointerReportsCannotLeak() throws {
        var decoder = TerminalPointerInputDecoder()
        #expect(try decoder.consume(Data([27])).isEmpty)
        if case .keyboard(let bytes) = decoder.flushPending().first { #expect(bytes == Data([27])) }
        else { Issue.record("Escape was lost") }
        #expect(try decoder.consume(Data("\u{1B}[<64;1;".utf8)).isEmpty)
        #expect(decoder.flushPending().isEmpty)
        #expect(throws: BridgeError.self) { _ = try decoder.consume(Data(("\u{1B}[<" + String(repeating: "1", count: 129)).utf8)) }
    }
    @Test func wheelPansCapturedRowsAndTypingReturnsToTheComposer() async throws {
        let workspace = UUID().uuidString, surface = UUID().uuidString
        let frame = try MobileTerminalRenderGridFrame(surfaceID: surface, stateSeq: 1, renderEpoch: "producer", columns: 104,
            rows: 26, cursor: .init(row: 23, column: 3), rowSpans: [.init(row: 0, column: 0, text: "HEADER"), .init(row: 23, column: 0, text: "INPUT")])
        let payload: JSONValue = .object(["workspace_id": .string(workspace), "surface_id": .string(surface),
            "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
        let snapshot = try TerminalSnapshotRenderer().render(payload, workspaceID: workspace, surfaceID: surface)
        let position = TerminalViewportState()
        #expect(await position.topRow(for: snapshot, localRows: 21) == nil)
        await position.scroll(-3); await position.scroll(-3)
        let top = await position.topRow(for: snapshot, localRows: 21)
        #expect(top == 0)
        let scrolled = try TerminalViewportPresentation().render(snapshot, columns: 78, rows: 21, topRow: top)
        #expect(scrolled.renderGrid?["cursor"]["visible"].bool == false)
        #expect(scrolled.renderGrid?["row_spans"].array?.compactMap { $0["text"].string }.joined().contains("HEADER") == true)
        await position.followCursor()
        let follow = await position.topRow(for: snapshot, localRows: 21)
        #expect(follow == nil)
        let returned = try TerminalViewportPresentation().render(snapshot, columns: 78, rows: 21, topRow: follow)
        #expect(returned.renderGrid?["cursor"]["visible"].bool == true)
        #expect(returned.renderGrid?["cursor"]["row"].int == 18)
    }
}
