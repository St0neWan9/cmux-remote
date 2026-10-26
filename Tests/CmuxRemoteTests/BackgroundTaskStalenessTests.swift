import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Endings that leave no completion notice must still end the task: a Monitor's own timeout, a
/// `TaskStop`, and the end of the agent process that started it.
@Suite struct BackgroundTaskStalenessTests {
    private func row(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private func call(_ id: String, _ name: String, _ input: [String: Any], at stamp: String = "2026-10-14T10:00:00.000Z") -> String {
        row(["type": "assistant", "timestamp": stamp, "message": ["content": [["type": "tool_use", "id": id, "name": name, "input": input]]]])
    }
    private func result(_ id: String, _ text: String) -> String {
        row(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": text]]]])
    }
    private func date(_ text: String) -> Date { try! Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    @Test func aMonitorEndsAtItsDeclaredTimeout() {
        let rows = [call("m", "Monitor", ["command": "tail -f log", "description": "watch", "timeout_ms": 600_000])]
        let tracker = BackgroundTaskTracker()
        #expect(tracker.running(in: rows, at: date("2026-10-14T10:09:59.000Z")).map(\.id) == ["m"])
        #expect(tracker.running(in: rows, at: date("2026-10-14T10:10:00.000Z")).isEmpty)
    }
    @Test func aMonitorWithoutATimeoutUsesTheDefaultAndNoneOutlivesTheCeiling() {
        let tracker = BackgroundTaskTracker()
        let plain = [call("m", "Monitor", ["command": "x", "description": "watch"])]
        #expect(tracker.running(in: plain, at: date("2026-10-14T10:04:59.000Z")).count == 1)
        #expect(tracker.running(in: plain, at: date("2026-10-14T10:05:01.000Z")).isEmpty)
        let long = [call("m", "Monitor", ["command": "x", "description": "watch", "timeout_ms": 99_000_000])]
        #expect(tracker.running(in: long, at: date("2026-10-14T11:00:01.000Z")).isEmpty)
    }
    /// A re-armed watch leaves a launch every half hour; only the newest can still be running.
    @Test func aReArmedMonitorShowsOnlyTheLiveOne() {
        let rows = (0..<6).map { index in
            call("m\(index)", "Monitor", ["command": "x", "description": "watch", "timeout_ms": 1_800_000],
                 at: String(format: "2026-10-14T%02d:00:00.000Z", 10 + index))
        }
        #expect(BackgroundTaskTracker().running(in: rows, at: date("2026-10-14T15:10:00.000Z")).map(\.id) == ["m5"])
    }
    /// `TaskStop` names the task id each launch result reported, in each tool's own wording.
    @Test func taskStopEndsTheTaskItNames() {
        let rows = [
            call("b", "Bash", ["command": "serve", "description": "Serve", "run_in_background": true]),
            result("b", "Command running in background with ID: bbwlrjilk. Output is being written to: /tmp/x"),
            call("m", "Monitor", ["command": "x", "description": "watch", "timeout_ms": 3_600_000]),
            result("m", "Monitor started (task b3czjkc3t, expires in 30m unless the source ends first)."),
            call("a", "Agent", ["prompt": "x", "description": "Research", "run_in_background": true]),
            result("a", "Async agent launched successfully.\nagentId: a811001284c0c1207 (internal ID)"),
            call("s1", "TaskStop", ["task_id": "bbwlrjilk"]),
            call("s2", "TaskStop", ["task_id": "b3czjkc3t"]),
        ]
        let running = BackgroundTaskTracker().running(in: rows, at: date("2026-10-14T10:01:00.000Z"))
        #expect(running.map(\.id) == ["a"])
    }
    @Test func aStopNamingAnUnknownTaskEndsNothing() {
        let rows = [call("b", "Bash", ["command": "serve", "description": "Serve", "run_in_background": true]),
                    result("b", "Command running in background with ID: bbwlrjilk."),
                    call("s", "TaskStop", ["task_id": "someoneelse"])]
        #expect(BackgroundTaskTracker().running(in: rows, at: Date()).map(\.id) == ["b"])
    }

    // MARK: Reader

    private func write(_ rows: [String]) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: file)
        return file.path
    }
    /// One reader serves every conversation, and an unchanged record is answered from its cache; that
    /// cache must not hand one conversation another's tasks.
    @Test func anUnchangedRecordKeepsItsOwnTasks() async throws {
        let withTask = try write([call("b", "Bash", ["command": "serve", "description": "Serve", "run_in_background": true])])
        let without = try write([row(["type": "user", "uuid": "u", "message": ["content": "Hello"]])])
        defer { try? FileManager.default.removeItem(atPath: withTask); try? FileManager.default.removeItem(atPath: without) }
        let reader = TranscriptReader()
        #expect(try await reader.history(path: withTask, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.map(\.id) == ["b"])
        #expect(try await reader.history(path: without, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.isEmpty == true)
        // Both now come from the cache.
        #expect(try await reader.history(path: withTask, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.map(\.id) == ["b"])
        #expect(try await reader.history(path: without, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.isEmpty == true)
    }
    /// A Monitor's deadline passes while the record stays unchanged, so the cached answer must still expire.
    @Test func aCachedMonitorExpiresWithTime() async throws {
        let path = try write([call("m", "Monitor", ["command": "x", "description": "watch", "timeout_ms": 60_000])])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let clock = Clock(date("2026-10-14T10:00:30.000Z"))
        let reader = TranscriptReader(now: { clock.value })
        #expect(try await reader.history(path: path, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.count == 1)
        clock.value = date("2026-10-14T10:01:01.000Z")
        #expect(try await reader.history(path: path, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.isEmpty == true)
    }
    /// An ended agent's tasks ended with it; the empty list, not an absent one, clears what the phone showed.
    @Test func anEndedSessionReportsNoTasks() async throws {
        let path = try write([call("b", "Bash", ["command": "serve", "description": "Serve", "run_in_background": true])])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let snapshot = try await TranscriptReader().history(path: path, agent: "claude", beforeSeq: nil, limit: 50, reportsBackgroundTasks: false)
        #expect(snapshot.backgroundTasks == [])
    }
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock(); private var stored: Date
        init(_ date: Date) { stored = date }
        var value: Date { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
    }

    // MARK: Retries

    private func notice(_ id: String, _ status: String, at stamp: String) -> String {
        let text = "<task-notification>\n<task-id>t\(id)</task-id>\n<tool-use-id>\(id)</tool-use-id>\n<status>\(status)</status>\n</task-notification>"
        return row(["type": "queue-operation", "timestamp": stamp, "content": text])
    }
    /// A failure ends the task but keeps the launch: Claude Code retries the agent under the same id.
    @Test func aFailureKeepsTheLaunchForARetry() {
        var state = BackgroundTaskTracker.State()
        BackgroundTaskTracker().consume([
            call("a", "Agent", ["prompt": "x", "description": "Audit", "run_in_background": true]),
            result("a", "Async agent launched successfully.\nagentId: ag1 (internal ID)"),
            notice("a", "failed", at: "2026-10-14T10:01:00.000Z"),
        ], into: &state)
        #expect(state.launched.isEmpty)
        #expect(state.failed["a"]?.launch.task.id == "a")
        #expect(state.taskIDByToolUse["a"] == "ag1")
    }
    /// A completion is final, and `TaskStop` ends a failed task for good.
    @Test func aCompletionOrStopEndsTheTaskWithoutKeepingIt() {
        var completed = BackgroundTaskTracker.State()
        BackgroundTaskTracker().consume([
            call("a", "Agent", ["prompt": "x", "description": "Audit", "run_in_background": true]),
            result("a", "Async agent launched successfully.\nagentId: ag1 (internal ID)"),
            notice("a", "completed", at: "2026-10-14T10:01:00.000Z"),
        ], into: &completed)
        #expect(completed.launched.isEmpty && completed.failed.isEmpty)
        var stopped = BackgroundTaskTracker.State()
        BackgroundTaskTracker().consume([
            call("b", "Bash", ["command": "x", "description": "Serve", "run_in_background": true]),
            result("b", "Command running in background with ID: bbwlrjilk."),
            notice("b", "failed", at: "2026-10-14T10:01:00.000Z"),
            call("s", "TaskStop", ["task_id": "bbwlrjilk"]),
        ], into: &stopped)
        #expect(stopped.failed.isEmpty)
    }
    /// The retry writes no launch row: only the agent's own record, touched after the notice, shows it.
    private func retriedTranscript() throws -> (path: String, record: URL) {
        let path = try write([
            call("a", "Agent", ["prompt": "x", "description": "Audit", "run_in_background": true]),
            result("a", "Async agent launched successfully.\nagentId: ag1 (internal ID)"),
            notice("a", "failed", at: "2026-10-14T10:01:00.000Z"),
        ])
        let records = URL(fileURLWithPath: path).deletingPathExtension().appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        let record = records.appendingPathComponent("agent-ag1.jsonl")
        try Data("{}\n".utf8).write(to: record)
        return (path, record)
    }
    @Test func aRetriedAgentComesBackWhileItsRecordIsWritten() async throws {
        let (path, record) = try retriedTranscript()
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingPathExtension()) }
        try FileManager.default.setAttributes([.modificationDate: date("2026-10-14T10:03:00.000Z")], ofItemAtPath: record.path)
        let moment = date("2026-10-14T10:05:00.000Z")
        let reader = TranscriptReader(now: { moment })
        #expect(try await reader.history(path: path, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.map(\.id) == ["a"])
    }
    /// A record written before the notice is the task that just died, not a retry.
    @Test func aFailureWhoseRecordStoppedDoesNotComeBack() async throws {
        let (path, record) = try retriedTranscript()
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingPathExtension()) }
        try FileManager.default.setAttributes([.modificationDate: date("2026-10-14T10:00:30.000Z")], ofItemAtPath: record.path)
        let moment = date("2026-10-14T10:05:00.000Z")
        let reader = TranscriptReader(now: { moment })
        #expect(try await reader.history(path: path, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.isEmpty == true)
    }
    /// A retried agent that stops writing leaves the list again.
    @Test func aRetriedAgentWhoseRecordGoesQuietLeavesTheList() async throws {
        let (path, record) = try retriedTranscript()
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingPathExtension()) }
        try FileManager.default.setAttributes([.modificationDate: date("2026-10-14T10:03:00.000Z")], ofItemAtPath: record.path)
        let moment = date("2026-10-14T10:30:00.000Z")
        let reader = TranscriptReader(now: { moment })
        #expect(try await reader.history(path: path, agent: "claude", beforeSeq: nil, limit: 50).backgroundTasks?.isEmpty == true)
    }
}
