import Foundation
import SQLite3
import Testing
import TermRemoteCore
@testable import TermRemoteBridge
import CmuxAgentChat

@Suite struct AntigravityTests {
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("antigravity-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func parsesUserInputThinkingProseToolsAndIncrementalResults() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transcript_full.jsonl")
        let chunk1 = [
            #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-20T18:41:37Z","content":"<USER_REQUEST>\nAdd Antigravity support\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nThe current local time is: 2026-11-21T01:41:37+07:00.\n</ADDITIONAL_METADATA>"}"#,
            #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-20T18:41:40Z","model":"gemini-4-neon-high","thinking":"Inspecting the repository layout.","tool_calls":[{"name":"run_command","args":{"CommandLine":"git status -s","toolSummary":"Check git status"}},{"name":"read_file","args":{"Path":"/tmp/project/README.md"}},{"name":"edit_file","args":{"Path":"/tmp/project/File.swift","Target":"let a = 1","Replacement":"let a = 2"}},{"name":"write_file","args":{"Path":"/tmp/project/New.swift","Content":"struct New {}"}}]}"#,
            #"{"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","created_at":"2026-11-20T18:41:41Z","content":"Created At: 2026-11-21T01:41:40+07:00\nCompleted At: 2026-11-21T01:41:41+07:00\nCommand exited with code 0.\n\nCommand output:\n M Sources/File.swift"}"#
        ].joined(separator: "\n") + "\n"
        try Data(chunk1.utf8).write(to: file)

        let reader = TranscriptReader()
        let first = try await reader.history(path: file.path, agent: "antigravity", beforeSeq: nil, limit: 100)
        #expect(first.agentModel?.model == "gemini-4-neon-high")

        // User prompt has <USER_REQUEST> wrapper and metadata stripped cleanly.
        let userMessage = try #require(first.messages.first { $0.role == .user })
        if case .prose(let prose) = userMessage.kind {
            #expect(prose.text == "Add Antigravity support")
        } else {
            Issue.record("Expected user prose message")
        }

        // First tool (run_command) already paired with step_index 2.
        let commandMessage = try #require(first.messages.first {
            if case .terminal = $0.kind { return true } else { return false }
        })
        if case .terminal(let terminal) = commandMessage.kind {
            #expect(terminal.command == "git status -s")
            #expect(terminal.summary == "Check git status")
            #expect(terminal.exitCode == 0)
            #expect(terminal.output == " M Sources/File.swift")
            #expect(!terminal.isRunning)
        }

        // Second tool (read_file) is still running until its GENERIC result arrives in chunk 2.
        let pendingRead = try #require(first.messages.first {
            if case .toolUse(let tool) = $0.kind { return tool.toolName == "Read" } else { return false }
        })
        if case .toolUse(let tool) = pendingRead.kind {
            #expect(tool.status == .running)
            #expect(tool.referencedPaths == ["/tmp/project/README.md"])
        }

        // Append step 3 (read_file result), step 6 (internal SYSTEM_MESSAGE skipped), and step 7 (final prose).
        let chunk2 = [
            #"{"step_index":3,"source":"MODEL","type":"GENERIC","status":"DONE","created_at":"2026-11-20T18:41:42Z","content":"Created At: 2026-11-21T01:41:41+07:00\nCompleted At: 2026-11-21T01:41:42+07:00\n# Project"}"#,
            #"{"step_index":6,"source":"SYSTEM","type":"SYSTEM_MESSAGE","status":"DONE","created_at":"2026-11-20T18:41:43Z","content":"The following is a <SYSTEM_MESSAGE> not actually sent by the user."}"#,
            #"{"step_index":7,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-20T18:41:45Z","model":"gemini-4-neon-high","content":"All done."}"#
        ].joined(separator: "\n") + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(chunk2.utf8))
        try handle.close()

        let second = try await reader.history(path: file.path, agent: "antigravity", beforeSeq: nil, limit: 100)
        #expect(second.generation == first.generation)
        #expect(second.currentTurnCompleted == true)

        // Incremental append paired step 3 back onto the original Read message by ID.
        let completedRead = try #require(second.messages.first { $0.id == pendingRead.id })
        if case .toolUse(let tool) = completedRead.kind {
            #expect(tool.status == .succeeded)
            #expect(tool.output == "# Project")
        } else {
            Issue.record("Expected completed Read toolUse")
        }

        // SYSTEM_MESSAGE was not emitted; final prose was emitted.
        #expect(!second.messages.contains {
            if case .prose(let prose) = $0.kind { return prose.text.contains("<SYSTEM_MESSAGE>") } else { return false }
        })
        let finalProse = try #require(second.messages.last)
        if case .prose(let prose) = finalProse.kind {
            #expect(prose.text == "All done.")
        } else {
            Issue.record("Expected final agent prose")
        }

        // Tool detail pagination works on Antigravity tool records.
        let detail = try await reader.toolText(path: file.path, agent: "antigravity", messageID: completedRead.id,
                                               generation: second.generation, field: "output", offset: 0, contentID: nil, limit: 100)
        #expect(detail.text == "# Project")
    }

    @Test func partialLineAndTruncationReanchorForAntigravity() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transcript_full.jsonl")
        let line1 = #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-20T18:41:37Z","content":"<USER_REQUEST>\nFirst\n</USER_REQUEST>"}"#
        let partial = #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"Second"}"#
        try Data((line1 + "\n" + partial).utf8).write(to: file)

        let reader = TranscriptReader()
        let before = try await reader.history(path: file.path, agent: "antigravity", beforeSeq: nil, limit: 100)
        #expect(before.messages.count == 1)

        // Replace with shorter file -> generation must change.
        let replacement = #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","content":"New"}"# + "\n"
        try Data(replacement.utf8).write(to: file)
        let after = try await reader.history(path: file.path, agent: "antigravity", beforeSeq: nil, limit: 100)
        #expect(after.generation != before.generation)
        #expect(after.messages.count == 1)
    }

    @Test func proseScreenExtractorReadsStreamingAnswerAboveBrailleSpinner() {
        let lines = [
            "● Explored 2 files (README.md, Package.swift)",
            "Streaming answer line one.",
            "Streaming answer line two.",
            "⣷  Thinking...",
            "└ Tip: In /diff, press c to add inline comments.",
            "────────────────────────────────────────────────────────",
            ">",
            "────────────────────────────────────────────────────────",
            "esc to cancel                               auto · Gemini 4 Neon · high"
        ]
        let extracted = AntigravityProseScreenExtractor().extract(lines: lines)
        #expect(extracted == "Streaming answer line one.\nStreaming answer line two.")

        let noProse = [
            "Old committed prose that must never leak.",
            "● Ran (git status)",
            "● Running (xcodebuild test ...) (ctrl+o to expand)",
            "⣷  Running command...",
            "────────────────────────────────────────────────────────",
            ">",
            "────────────────────────────────────────────────────────",
            "esc to cancel                               auto · Gemini 4 Neon · high"
        ]
        #expect(AntigravityProseScreenExtractor().extract(lines: noProse) == nil)

        // An idle screen whose scrollback prose mentions "esc to cancel" must never anchor on scrollback.
        let idleWithScrollbackMention = [
            "Old committed answer discussing the extractor.",
            "  esc to cancel anchors live previews.",
            "● Ran (git status)",
            "Some later committed answer.",
            "",
            "────────────────────────────────────────────────────────",
            ">",
            "────────────────────────────────────────────────────────",
            "? for shortcuts                             auto · Gemini 4 Neon · high"
        ]
        #expect(AntigravityProseScreenExtractor().extract(lines: idleWithScrollbackMention) == nil)
    }

    @Test func promptSafetyValidatesAntigravityComposerAndBlocksDraftsOrDialogs() {
        let safety = TuiPromptSafety()
        let emptyRunning = [
            "⣷  Running command...",
            "────────────────────────────────────────",
            ">",
            "────────────────────────────────────────",
            "esc to cancel          auto · Gemini 4 Neon · high"
        ].joined(separator: "\n")
        #expect(safety.isEmpty(emptyRunning, provider: "antigravity"))

        let withDraft = [
            "────────────────────────────────────────",
            "> half typed draft",
            "────────────────────────────────────────",
            "auto · Gemini 4 Neon · high"
        ].joined(separator: "\n")
        #expect(!safety.isEmpty(withDraft, provider: "antigravity"))

        let withDialog = [
            "────────────────────────────────────────",
            ">",
            "────────────────────────────────────────",
            "Enter to select · Esc to go back"
        ].joined(separator: "\n")
        #expect(!safety.isEmpty(withDialog, provider: "antigravity"))

        // Bare shell continuation prompt without Antigravity dividers must never be accepted.
        #expect(!safety.isEmpty("> ", provider: "antigravity"))
    }

    @Test func processRegistryProvesSessionFromPresenceLockAndMetadata() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let appData = root.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
        let presence = appData.appendingPathComponent("presence", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let sessionID = UUID().uuidString.lowercased()
        let logs = appData.appendingPathComponent("brain/\(sessionID)/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: presence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let lockFile = presence.appendingPathComponent("\(sessionID).lock")
        try Data().write(to: lockFile)

        // Create SQLite conversation_summaries.db with title, status and workspace_uris.
        let dbURL = appData.appendingPathComponent("conversation_summaries.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let createSQL = "CREATE TABLE conversation_summaries (conversation_id text PRIMARY KEY, title text, status text, workspace_uris text);"
        #expect(sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK)
        let uriJSON = "[\"\(project.absoluteString)\"]"
        var insert: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "INSERT INTO conversation_summaries VALUES (?, ?, ?, ?);", -1, &insert, nil) == SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(insert, 1, sessionID, -1, transient)
        sqlite3_bind_text(insert, 2, "Support Antigravity", -1, transient)
        sqlite3_bind_text(insert, 3, "CASCADE_RUN_STATUS_RUNNING", -1, transient)
        sqlite3_bind_text(insert, 4, uriJSON, -1, transient)
        #expect(sqlite3_step(insert) == SQLITE_DONE)
        sqlite3_finalize(insert)

        let registry = AntigravityProcessRegistry(root: appData, openFiles: { _ in [lockFile.path] })

        // Works even before transcript_full.jsonl is created (brand-new session).
        let pending = try #require(registry.binding(pid: 1234, cwd: project.path, roots: [appData]))
        #expect(pending.sessionID == sessionID)
        #expect(pending.title == "Support Antigravity")
        #expect(pending.conversationState == "working")
        #expect(!pending.transcriptExists)
        #expect(pending.transcript.hasSuffix("/brain/\(sessionID)/.system_generated/logs/transcript_full.jsonl"))

        // Rejects mismatched cwd and disallowed roots.
        #expect(registry.binding(pid: 1234, cwd: "/tmp/other", roots: [appData]) == nil)
        #expect(registry.binding(pid: 1234, cwd: project.path, roots: [root.appendingPathComponent("other-root")]) == nil)

        // Rejects symlinked lock files.
        let symlinkID = UUID().uuidString.lowercased()
        let outside = root.appendingPathComponent("outside.lock")
        try Data().write(to: outside)
        let symlinkLock = presence.appendingPathComponent("\(symlinkID).lock")
        try FileManager.default.createSymbolicLink(at: symlinkLock, withDestinationURL: outside)
        let symlinkRegistry = AntigravityProcessRegistry(root: appData, openFiles: { _ in [symlinkLock.path] })
        #expect(symlinkRegistry.binding(pid: 1234, cwd: project.path, roots: [appData]) == nil)
    }

    @Test func launchAndResumeCommandsForAntigravity() {
        #expect(LaunchAgent.antigravity.command == "agy --dangerously-skip-permissions")
        #expect(!LaunchAgent.antigravity.requiresPrompt)
        #expect(LaunchAgent.antigravity.resumeCommand(sessionID: "49F96599-CB55-4395-9B1E-24C790123008")
                == "agy --dangerously-skip-permissions --conversation=49f96599-cb55-4395-9b1e-24c790123008")

        let cmd = AgentCommandLine()
        #expect(cmd.line(.antigravity, prompt: nil) == "agy --dangerously-skip-permissions")
        #expect(cmd.line(.antigravity, prompt: "-start with dash") == "agy --dangerously-skip-permissions --prompt-interactive='-start with dash'")
    }
}
