import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// A conversation is named after the tab the owner named, as a workspace is; renaming the tab renames it.
@Suite struct TuiTabTitleTests {
    private func snapshot(tabName: JSONValue?) throws -> TuiSessionSnapshot {
        var root = TuiResourceFixture.graph(provider: "claude").object!
        var tab = root["tabs"]!.array![0].object!
        if let tabName { tab["name"] = tabName }
        root["tabs"] = .array([.object(tab)])
        return try TuiSessionSnapshot(.object(root))
    }
    @Test func theTabNameNamesTheConversation() throws {
        #expect(try snapshot(tabName: .string("Studio Cmux Remote Mobile")).bindings.first?.title == "Studio Cmux Remote Mobile")
    }
    @Test func anUnnamedTabFallsBackToTheTerminalTitle() throws {
        #expect(try snapshot(tabName: nil).bindings.first?.title == "Fixture Agent")
        #expect(try snapshot(tabName: .string("   ")).bindings.first?.title == "Fixture Agent")
        #expect(try snapshot(tabName: .null).bindings.first?.title == "Fixture Agent")
    }
}
