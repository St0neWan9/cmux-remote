import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct TuiHookStateTests {
    private func service(_ source: TuiResourceFixture, window: UInt64 = 20_000) -> (SessionService, TuiControlAdapter) {
        let home = URL(fileURLWithPath: "/nonexistent-fixture")
        let adapter = TuiControlAdapter(client: source, transcripts: .init(claudeRoot: home.appendingPathComponent(".claude"), codexRoot: home.appendingPathComponent(".codex")),
                                        restoreChecks: 1, restoreInterval: .milliseconds(1), journalWindow: window)
        return (SessionService(cmux: adapter, home: home, transcriptRoots: [home.appendingPathComponent(".claude")]), adapter)
    }
    private func state(_ session: SessionService) async throws -> String { try #require(try await session.sessions().first).state }

    @Test func aFailedToolKeepsTheTurnRunningAndStopEndsIt() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        _ = try await session.sessions()
        await source.hook("UserPromptSubmit"); await source.hook("PreToolUse", tool: "Bash"); await source.hook("PostToolUseFailure", tool: "Bash")
        await source.setAgentField("state", .string("blocked"))
        #expect(try await state(session) == "working")
        await source.hook("Stop"); await source.setAgentField("state", .string("idle"))
        #expect(try await state(session) == "idle")
    }
    @Test func aCompactionInsideATurnKeepsItRunning() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        _ = try await session.sessions()
        await source.hook("UserPromptSubmit"); await source.hook("PreCompact"); await source.hook("SessionStart", source: "compact")
        await source.setAgentField("state", .string("idle"))
        #expect(try await state(session) == "working")
        await source.hook("SessionStart", source: "startup")
        #expect(try await state(session) == "idle")
    }
    @Test func questionsAndPermissionsNeedInputUntilTheToolRuns() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        _ = try await session.sessions()
        await source.hook("PreToolUse", tool: "AskUserQuestion")
        #expect(try await state(session) == "needs_input")
        await source.hook("PostToolUse", tool: "AskUserQuestion"); await source.hook("PreToolUse", tool: "Edit")
        #expect(try await state(session) == "working")
        await source.hook("PermissionRequest", tool: "Edit")
        #expect(try await state(session) == "needs_input")
        await source.hook("Notification", notification: "idle_prompt")
        #expect(try await state(session) == "idle")
    }
    @Test func theBootstrapWindowReplaysRecentHooksAndLaterReadsContinueWithoutGaps() async throws {
        let source = TuiResourceFixture()
        await source.hook("UserPromptSubmit"); await source.hook("PostToolUseFailure", tool: "Bash")
        await source.setAgentField("state", .string("blocked"))
        let (session, _) = service(source)
        #expect(try await state(session) == "working")
        let head = await source.journalHead
        await source.hook("Stop")
        #expect(try await state(session) == "idle")
        let reads = await source.journalReads
        // Head probe and one window replay from 0; every later read resumes at an earlier end instead of replaying.
        #expect(reads[0] == .null); #expect(reads[1]["revision"].string == "0")
        #expect(reads.filter { $0 == .null || $0["revision"].string == "0" }.count == 2)
        #expect(reads.contains { $0["revision"].string == String(head) })
    }
    @Test func aLongBacklogIsReadInBoundedPages() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        _ = try await session.sessions()
        for _ in 0..<1_500 { await source.hook("PreToolUse", tool: "Read", unrelated: 0) }
        await source.hook("Stop", unrelated: 0)
        #expect(try await state(session) == "idle")
        // The fixture never returns more than the requested 1,000 items, so the backlog took a cut page and a resume.
        #expect(await source.journalReads.contains { $0["revision"].string.flatMap(UInt64.init).map { $0 > 0 && $0 < 1_501 } == true })
    }
    @Test func anUnreadableJournalFallsBackToTheDaemonState() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        await source.hook("UserPromptSubmit"); await source.hook("PostToolUseFailure")
        await source.breakJournal(true); await source.setAgentField("state", .string("blocked"))
        #expect(try await state(session) == "needs_input")
        await source.breakJournal(false)
        #expect(try await state(session) == "working")
    }
    @Test func otherProvidersAndUnknownSessionsNeverOverrideTheDaemon() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        _ = try await session.sessions()
        await source.hook("UserPromptSubmit", provider: "codex"); await source.hook("UserPromptSubmit", session: "not-a-session")
        await source.setAgentField("state", .string("idle"))
        #expect(try await state(session) == "idle")
    }
    @Test func aPhoneInterruptEndsTheTurnWithoutAHook() async throws {
        let source = TuiResourceFixture(), (session, _) = service(source)
        await source.hook("UserPromptSubmit"); await source.setAgentField("state", .string("working"))
        let id = try #require(try await session.sessions().first?.id)
        #expect(try await state(session) == "working")
        _ = try await session.interrupt(id: id, request: .init())
        #expect(try await state(session) == "idle")
    }
}
