import Foundation
import Testing
import CmuxRemoteBridge
import CmuxRemoteCore

@Suite struct ResponseTimingTests {
    private func page(_ rows: [String], agent: String = "claude", limit: Int = 100) async throws -> ConversationSnapshot {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: file)
        return try await TranscriptReader().history(path: file.path, agent: agent, beforeSeq: nil, limit: limit)
    }
    private let user = #"{"type":"user","uuid":"u","timestamp":"2026-10-12T00:00:00Z","message":{"content":"Hello"}}"#
    private let reply = #"{"type":"assistant","uuid":"a","timestamp":"2026-10-12T00:00:10Z","message":{"content":[{"type":"text","text":"Reply"}]}}"#
    @Test func claudeInterruptionEndsCurrentTurnWithoutStartingASyntheticPrompt() async throws {
        let interrupted = #"{"type":"user","uuid":"interrupted","isSidechain":false,"timestamp":"2026-10-12T00:00:12Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let snapshot = try await page([user, reply, interrupted])
        #expect(snapshot.currentTurnCompleted == true)
        #expect(snapshot.currentTurnStartedAt == ISO8601DateFormatter().date(from: "2026-10-12T00:00:00Z"))
        #expect(snapshot.responses?.first?.completed == true)
        #expect(snapshot.responses?.first?.durationSeconds == 12)
        #expect(snapshot.responses?.first?.recordedDuration == false)
        #expect(snapshot.recordedRunSeconds == nil)
        let next = #"{"type":"user","uuid":"next","timestamp":"2026-10-12T00:01:00Z","message":{"content":"Continue"}}"#
        #expect(try await page([user, reply, interrupted, next]).currentTurnCompleted == false)
        let quoted = #"{"type":"user","uuid":"quoted","timestamp":"2026-10-12T00:01:00Z","message":{"content":"Explain [Request interrupted by user]"}}"#
        #expect(try await page([user, reply, quoted]).currentTurnCompleted == false)
    }
    @Test func recordedClaudeDurationExcludesIdleAndIgnoresSidechain() async throws {
        let snapshot = try await page([user, reply,
            #"{"type":"system","subtype":"turn_duration","isSidechain":true,"durationMs":999999,"timestamp":"2026-10-12T00:00:11Z"}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":13363,"timestamp":"2026-10-12T00:00:11Z"}"#,
            #"{"type":"user","uuid":"next","timestamp":"2026-10-12T04:00:00Z","message":{"content":"Next"}}"#])
        let response = try #require(snapshot.responses?.first)
        #expect(response.durationSeconds == 13.363)
        #expect(response.recordedDuration)
        #expect(response.firstMessageID == "a")
        #expect(response.lastMessageID == "a")
        #expect(snapshot.recordedRunSeconds == 13.363)
        #expect(snapshot.recordedTurnCount == 1)
    }
    @Test func absentCompletionIsNotFabricated() async throws {
        let snapshot = try await page([user, reply])
        let response = try #require(snapshot.responses?.first)
        #expect(response.completedAt == nil)
        #expect(response.durationSeconds == nil)
        #expect(snapshot.recordedRunSeconds == nil)
    }
    @Test func nextPromptProvidesOnlyAnEstimateAndUnknownTimestampsStayUnknown() async throws {
        let next = #"{"type":"user","uuid":"next","timestamp":"2026-10-12T04:00:00Z","message":{"content":"Next"}}"#
        let snapshot = try await page([user, reply, next])
        #expect(snapshot.responses?.first?.durationSeconds == 10)
        #expect(snapshot.responses?.first?.recordedDuration == false)
        #expect(snapshot.recordedRunSeconds == nil)
        // Inherited parser timestamps must not imply source precision.
        let unstamped = #"{"type":"assistant","uuid":"a","message":{"content":[{"type":"text","text":"Reply"}]}}"#
        let unknown = try await page([user, unstamped, next])
        #expect(unknown.responses?.first?.completedAt == nil)
        #expect(unknown.responses?.first?.durationSeconds == nil)
    }
    @Test func codexLifecycleStartsBeforeUserAndCompletesAfterReply() async throws {
        let snapshot = try await page([
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:00Z","payload":{"type":"task_started","turn_id":"t"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:01Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:05Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Reply"}]}}"#,
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:07Z","payload":{"type":"task_complete","turn_id":"t"}}"#], agent: "codex")
        #expect(snapshot.responses?.first?.durationSeconds == 7)
        #expect(snapshot.responses?.first?.recordedDuration == true)
    }
    @Test func toolOnlyInterruptedTurnStillCountsRecordedDuration() async throws {
        let snapshot = try await page([
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:00Z","payload":{"type":"task_started","turn_id":"t"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:01Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:05Z","payload":{"type":"function_call","call_id":"call","name":"exec_command","arguments":"{}"}}"#,
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:10Z","payload":{"type":"turn_aborted","turn_id":"t"}}"#], agent: "codex")
        #expect(snapshot.recordedRunSeconds == 10)
        #expect(snapshot.recordedTurnCount == 1)
    }
    @Test func outputFreeAbortStillCountsAndIsCompleted() async throws {
        let snapshot = try await page([
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:00Z","payload":{"type":"task_started","turn_id":"t"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:01Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}"#,
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:10Z","payload":{"type":"turn_aborted","turn_id":"t"}}"#], agent: "codex")
        #expect(snapshot.recordedRunSeconds == 10)
        #expect(snapshot.recordedTurnCount == 1)
        #expect(snapshot.currentTurnCompleted == true)
        #expect(snapshot.responses?.isEmpty == true)
    }
    @Test func attachmentOnlyPromptResetsTheCompletedTurn() async throws {
        let snapshot = try await page([user, reply,
            #"{"type":"system","subtype":"turn_duration","durationMs":10000,"timestamp":"2026-10-12T00:00:11Z"}"#,
            #"{"type":"user","uuid":"image","timestamp":"2026-10-12T01:00:00Z","message":{"content":"/tmp/clipboard-2026-10-12-010000-abcdef12.png"}}"#,
            #"{"type":"assistant","uuid":"a2","timestamp":"2026-10-12T01:00:05Z","message":{"content":[{"type":"text","text":"Image reply"}]}}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":5000,"timestamp":"2026-10-12T01:00:06Z"}"#])
        #expect(snapshot.recordedRunSeconds == 15)
        #expect(snapshot.recordedTurnCount == 2)
        #expect(snapshot.responses?.last?.lastMessageID == "a2")
        #expect(snapshot.currentTurnCompleted == true)
    }
    @Test func unknownPromptStampDoesNotInheritEarlierTimestamp() async throws {
        let snapshot = try await page([user, reply,
            #"{"type":"system","subtype":"turn_duration","durationMs":10000,"timestamp":"2026-10-12T00:00:11Z"}"#,
            #"{"type":"user","uuid":"new","message":{"content":"New unstamped prompt"}}"#])
        #expect(snapshot.currentTurnStartedAt == nil)
        #expect(snapshot.currentTurnCompleted == false)
    }
    @Test func malformedDurationAndUnrelatedCodexCompletionStayUnknown() async throws {
        let snapshot = try await page([user, reply,
            #"{"type":"system","subtype":"turn_duration","durationMs":true,"timestamp":"2026-10-12T00:00:11Z"}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":-100,"timestamp":"2026-10-12T00:00:11Z"}"#])
        #expect(snapshot.recordedRunSeconds == nil)
        #expect(snapshot.currentTurnCompleted == false)
        let unrelated = try await page([
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:00Z","payload":{"type":"task_started","turn_id":"t"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T00:00:01Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}"#,
            #"{"type":"event_msg","timestamp":"2026-10-12T00:00:10Z","payload":{"type":"task_complete","turn_id":"other"}}"#], agent: "codex")
        #expect(unrelated.recordedRunSeconds == nil)
        #expect(unrelated.currentTurnCompleted == false)
    }
    @Test func paginationKeepsWholeSessionRecordedTotalAndLegacyWireDecodes() async throws {
        let snapshot = try await page([user, reply,
            #"{"type":"system","subtype":"turn_duration","durationMs":13363,"timestamp":"2026-10-12T00:00:11Z"}"#], limit: 1)
        #expect(snapshot.messages.count == 1)
        #expect(snapshot.recordedRunSeconds == 13.363)
        #expect(snapshot.responses?.count == 1)
        let legacy = try JSONDecoder().decode(ConversationSnapshot.self, from: Data(#"{"messages":[],"hasMore":false,"generation":"g","clipped":false}"#.utf8))
        #expect(legacy.responses == nil)
    }
}
