import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct TuiInterruptedStateTests {
    private func adapter(_ source: TuiResourceFixture) -> TuiControlAdapter {
        TuiControlAdapter(client: source, transcripts: .init(claudeRoot: URL(fileURLWithPath: "/nonexistent-fixture/.claude"), codexRoot: URL(fileURLWithPath: "/nonexistent-fixture/.codex")))
    }
    private func state(_ source: TuiResourceFixture) async throws -> String? {
        try await adapter(source).request("chat.sessions.dump", params: [:])["sessions"].array?.first?["state"].string
    }

    @Test func anInterruptedClaudeTurnIsIdleOnceTheTitleSaysSo() async throws {
        let source = TuiResourceFixture()
        await source.setAgentField("state", .string("working"))
        // Interrupting Claude sends no Stop hook; its title returns to the idle mark.
        await source.setTerminalField("title", .string("✳ Fixture Agent"))
        #expect(try await state(source) == "idle")
        await source.setTerminalField("title", .string("◐ Fixture Agent"))
        #expect(try await state(source) == "working")
    }

    @Test func otherAgentsAndStatesKeepWhatTheirHooksSay() async throws {
        let codex = TuiResourceFixture(provider: "codex")
        await codex.setAgentField("state", .string("working"))
        await codex.setTerminalField("title", .string("✳ Fixture Agent"))
        #expect(try await state(codex) == "working")
        let blocked = TuiResourceFixture()
        await blocked.setAgentField("state", .string("blocked"))
        await blocked.setTerminalField("title", .string("✳ Fixture Agent"))
        #expect(try await state(blocked) == "needs_input")
    }
}
