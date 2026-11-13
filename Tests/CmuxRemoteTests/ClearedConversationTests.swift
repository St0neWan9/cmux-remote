import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// `/clear` leaves the old conversation behind in its terminal; the list dates it so the phone can archive it.
@Suite struct ClearedConversationTests {
    private static let cleared = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); return root
    }
    private func service(_ source: TuiResourceFixture, root: URL) -> SessionService {
        let adapter = TuiControlAdapter(client: source, transcripts: .init(claudeRoot: root.appendingPathComponent(".claude"), codexRoot: root.appendingPathComponent(".codex")),
                                        archive: TuiBindingRepository(directory: root), restoreChecks: 1, restoreInterval: .milliseconds(1))
        return SessionService(cmux: adapter, home: root, transcriptRoots: [root.appendingPathComponent(".claude")])
    }
    private func message(_ type: String, _ text: String, at stamp: String, meta: Bool = false) -> String {
        let record: [String: Any] = ["type": type, "timestamp": stamp, "cwd": "/project", "isMeta": meta, "message": ["role": type, "content": text]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }
    /// The opening Claude Code writes for a session `/clear` started: a mode line, the command's caveat, the command
    /// itself and its local-command record, all dated when the command ran.
    private func clearOpening(at stamp: String) -> [String] {
        [#"{"type":"mode","mode":"normal"}"#,
         message("user", "<local-command-caveat>The command below was run directly.</local-command-caveat>", at: stamp, meta: true),
         message("user", "<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>", at: stamp),
         #"{"type":"system","subtype":"local_command","timestamp":"\#(stamp)","commandRun":{"command":"clear","args":""}}"#]
    }
    private func write(_ lines: [String], session: String, root: URL) throws {
        let folder = root.appendingPathComponent(".claude/projects/-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: folder.appendingPathComponent(session + ".jsonl"))
    }
    private func date(_ stamp: String) -> Date { try! Date(stamp, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    @Test func aClearedConversationEndsAndIsDatedByTheClear() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), session = service(source, root: root)
        try write([message("user", "first question", at: "2026-11-12T09:00:00.000Z"), message("assistant", "answer", at: "2026-11-12T09:05:00.000Z")],
                  session: TuiResourceFixture.providerID, root: root)
        let original = try #require(try await session.sessions().first)
        #expect(original.clearedAt == nil && original.writable)
        // `/clear` in the same terminal: the daemon now reports a new Agent session there.
        try write(clearOpening(at: "2026-11-12T10:00:00.000Z"), session: Self.cleared, root: root)
        await source.setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string(Self.cleared)]))
        let after = try await session.sessions()
        #expect(after.count == 2)
        let old = try #require(after.first { $0.id == original.id }), new = try #require(after.first { $0.id != original.id })
        // The new Agent's prompt is on that terminal; it is not the old conversation coming back.
        #expect(old.state == "ended" && !old.writable)
        #expect(old.clearedAt == date("2026-11-12T10:00:00.000Z"))
        #expect(new.clearedAt == nil && new.writable)
    }
    @Test func aConversationResumedAfterTheClearIsNotArchived() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), session = service(source, root: root)
        try write([message("user", "first question", at: "2026-11-12T09:00:00.000Z")], session: TuiResourceFixture.providerID, root: root)
        let original = try #require(try await session.sessions().first)
        try write(clearOpening(at: "2026-11-12T10:00:00.000Z"), session: Self.cleared, root: root)
        await source.setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string(Self.cleared)]))
        #expect(try await session.sessions().first { $0.id == original.id }?.clearedAt != nil)
        // `/resume` brings it back into the terminal and it takes a new message: it is a current conversation again.
        try write([message("user", "first question", at: "2026-11-12T09:00:00.000Z"), message("user", "back again", at: "2026-11-12T11:00:00.000Z")],
                  session: TuiResourceFixture.providerID, root: root)
        await source.setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string(TuiResourceFixture.providerID)]))
        let resumed = try #require(try await session.sessions().first { $0.id == original.id })
        #expect(resumed.clearedAt == nil && resumed.writable)
        // Once the resumed conversation has ended too, its later message still keeps it out of the archive.
        await source.setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string(Self.cleared)]))
        #expect(try await session.sessions().first { $0.id == original.id }?.clearedAt == nil)
    }
    /// The daemon dropped the terminal's hook row, so every conversation that ran there reads as revived by the Agent
    /// prompt on screen. That prompt is the newest one's; the conversation the clear replaced is over and takes no input.
    @Test func aClearOutranksARevivalGuessedFromTheScreen() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), session = service(source, root: root)
        try write([message("user", "first question", at: "2026-11-12T09:00:00.000Z")], session: TuiResourceFixture.providerID, root: root)
        let original = try #require(try await session.sessions().first)
        try write(clearOpening(at: "2026-11-12T10:00:00.000Z"), session: Self.cleared, root: root)
        await source.setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string(Self.cleared)]))
        _ = try await session.sessions()
        await source.clearAgents()
        let rows = try await service(source, root: root).sessions()
        let old = try #require(rows.first { $0.id == original.id }), new = try #require(rows.first { $0.id != original.id })
        #expect(old.clearedAt == date("2026-11-12T10:00:00.000Z") && old.state == "ended" && !old.writable)
        #expect(new.clearedAt == nil && new.writable)
    }
    @Test func theEarliestClearDatesAConversationAndLiveOnesNeverArchive() {
        let at = { (minute: Int) in Date(timeIntervalSince1970: TimeInterval(minute * 60)) }
        let rule = ClearedSessions()
        // A cleared at 10 by B; B cleared at 20 by C; A resumed over C at 25, then cleared at 30 by D.
        // A was used after the first clear, so only the last one leaves it behind; C was left by a resume, not a clear.
        let rows: [ClearedSessions.Entry] = [
            .init(id: "a", surfaceID: "T", live: false, lastMessage: at(26), clearedFrom: nil),
            .init(id: "b", surfaceID: "t", live: false, lastMessage: at(15), clearedFrom: at(10)),
            .init(id: "c", surfaceID: "t", live: false, lastMessage: at(22), clearedFrom: at(20)),
            .init(id: "d", surfaceID: "t", live: true, lastMessage: at(31), clearedFrom: at(30)),
            .init(id: "other", surfaceID: "u", live: false, lastMessage: at(1), clearedFrom: nil),
        ]
        #expect(rule.times(rows) == ["a": at(30), "b": at(20)])
        // The live conversation the clear started is never archived, even by a clear it did not make.
        let live = rule.times([.init(id: "x", surfaceID: "t", live: true, lastMessage: at(5), clearedFrom: nil),
                               .init(id: "y", surfaceID: "t", live: true, lastMessage: at(12), clearedFrom: at(10))])
        #expect(live.isEmpty)
    }
    @Test func onlyAnOpeningClearCounts() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("t.jsonl")
        func opening(_ lines: [String]) throws -> Date?? {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            return TranscriptOpening().clearedFrom(path: file.path)
        }
        #expect(try opening(clearOpening(at: "2026-11-12T10:00:00.000Z")) == .some(date("2026-11-12T10:00:00.000Z")))
        // A `/clear` typed later in a conversation is not how it began.
        #expect(try opening([message("user", "hello", at: "2026-11-12T09:00:00.000Z")] + clearOpening(at: "2026-11-12T10:00:00.000Z")) == .some(nil))
        // A file with no message yet does not tell, so it is read again once it grows.
        #expect(try opening([#"{"type":"mode","mode":"normal"}"#]) == nil)
    }
}
