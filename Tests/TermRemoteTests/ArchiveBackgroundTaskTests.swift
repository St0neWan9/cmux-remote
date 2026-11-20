import Foundation
import Testing
@testable import TermRemoteBridge

/// The archive's newest page parses only the record's last few hundred kilobytes. A shell started
/// before that stretch, and still running, used to vanish from the phone.
@Suite struct ArchiveBackgroundTaskTests {
    private func row(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }
    private func message(_ index: Int) throws -> String {
        try row(["type": "user", "uuid": "m\(index)", "timestamp": "2026-11-20T05:00:00.000Z",
                 "message": ["role": "user", "content": "filler \(index) " + String(repeating: "x", count: 2_000)]])
    }
    private func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8))
    }

    @Test func aShellLaunchedLongBeforeTheNewestPageStillShowsAndEndsWithItsNotice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        var text = try row(["type": "assistant", "uuid": "launch", "timestamp": "2026-11-20T05:09:00.000Z",
                            "message": ["content": [["type": "tool_use", "id": "bg", "name": "Bash",
                                                     "input": ["command": "serve", "description": "Serve", "run_in_background": true]]]]])
        text += try row(["type": "user", "uuid": "launched", "timestamp": "2026-11-20T05:09:01.000Z",
                         "message": ["content": [["type": "tool_result", "tool_use_id": "bg",
                                                  "content": "Command running in background with ID: bserve1."]]]])
        // About 700 KB of later conversation pushes the launch out of the newest page's window.
        for index in 0..<350 { text += try message(index) }
        try Data(text.utf8).write(to: file)
        let reader = TranscriptReader()

        // The first read never waits for the window scan: it answers from its own chunk as before.
        let first = try await reader.archive(path: file.path, agent: "claude", tail: 20, cursor: nil, limit: 20)
        #expect(!first.snapshot.messages.contains { $0.id == "launch" })
        await reader.waitForArchiveScansForTesting()
        // Once the background scan is in, the next refresh carries the early launch.
        let newest = try await reader.archive(path: file.path, agent: "claude", tail: 20, cursor: nil, limit: 20)
        #expect(newest.snapshot.backgroundTasks?.map(\.id) == ["bg"])

        // The completion notice arrives later; only the appended bytes are read, and the task ends.
        let notice = "<task-notification>\n<task-id>bserve1</task-id>\n<tool-use-id>bg</tool-use-id>\n<status>completed</status>\n</task-notification>"
        try append(try row(["type": "queue-operation", "timestamp": "2026-11-20T06:00:00.000Z", "content": notice]) + message(999), to: file)
        let after = try await reader.archive(path: file.path, agent: "claude", tail: 20, cursor: nil, limit: 20)
        #expect(after.snapshot.backgroundTasks?.isEmpty ?? true)

        // An ended conversation reports none, however far back the launch sits.
        let ended = try await TranscriptReader().archive(path: file.path, agent: "claude", tail: 20, cursor: nil, limit: 20,
                                                         reportsBackgroundTasks: false)
        #expect(ended.snapshot.backgroundTasks?.isEmpty ?? true)
    }
}
