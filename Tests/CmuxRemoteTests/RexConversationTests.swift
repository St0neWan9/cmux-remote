import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

/// Proves a Claude process inside an isolated Rex terminal from the agent's own
/// registry, without touching the owner's Claude files or Rex server.
@Suite struct RexConversationTests {
    @Test func aClaudeForegroundProcessBecomesAConversation() async throws {
        guard let executable = Self.rexExecutable() else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rex-conversation-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fakeClaude = root.appendingPathComponent("claude")
        try Data("#!/bin/sh\nprintf '❯\\302\\240\\n'\nexec -a claude /bin/sleep 300\n".utf8).write(to: fakeClaude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)
        let fakeCodex = root.appendingPathComponent("codex")
        try Data("#!/bin/sh\nprintf '› \\n'\nexec -a codex /bin/sleep 300\n".utf8).write(to: fakeCodex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let port = Int.random(in: 20_000...60_000)
        let state = root.appendingPathComponent("rex-state")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["server", "run", "--listen", "127.0.0.1:\(port)", "--allow-anonymous",
                             "--state-dir", state.path, "--restore=false", "--log-format", "text"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            for _ in 0..<30 where process.isRunning { Darwin.usleep(100_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        let endpoint = RexEndpoint.tcp(host: "127.0.0.1", port: port, tls: false)
        let client = RexControlClient(endpoint: endpoint)
        var welcome: RexControlClient.Welcome?
        for _ in 0..<40 {
            if let value = try? await client.connect() { welcome = value; break }
            try await Task.sleep(for: .milliseconds(150))
        }
        _ = try #require(welcome)

        let created = try await client.request("session.create", [
            "label": .string("binding-fixture"),
            "initial_windows": .array([.object([
                "layout": .object(["block": .object(["flavor": .string("com.superlogical.terminal.shell")])])
            ])])
        ])
        let sessionID = try #require(created["session_id"].string)
        let baseBlock = try #require(created["initial_windows"].array?.first?["block_ids"].array?.first?.string)
        let split = try await client.request("session.new_split", [
            "session_id": .string(sessionID),
            "anchor_id": .string(baseBlock),
            "direction": .string("horizontal"),
            "side": .string("after"),
            "focus": .bool(false),
            "layout": .object(["block": .object([
                "flavor": .string("com.superlogical.terminal.shell"),
                "options": .object([
                    "command": .array([.string(fakeClaude.path), .string("300")]),
                    "cwd": .string(project.path),
                    "interactive": .bool(false)
                ])
            ])])
        ])
        let claudeBlock = try #require(split["block_ids"].array?.first?.string)

        var pid: Int?
        for _ in 0..<40 {
            if let info = try? await client.request("com.superlogical.terminal.process", [
                "session_id": .string(sessionID), "block_id": .string(claudeBlock), "args": .object([:])
            ]), (info["foreground"]["argv0"].string ?? info["foreground"]["name"].string) == "claude" {
                pid = info["foreground"]["pid"].int
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let processID = try #require(pid)

        let agentSession = UUID().uuidString.lowercased()
        let registry: [String: JSONValue] = [
            "pid": .number(Double(processID)), "sessionId": .string(agentSession),
            "cwd": .string(project.path), "status": .string("idle"),
            "procStart": .string("fixture"), "kind": .string("interactive")
        ]
        try JSONEncoder().encode(registry).write(to: home.appendingPathComponent(".claude/sessions/\(processID).json"))
        let encoded = String(project.path.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
        let transcriptDirectory = home.appendingPathComponent(".claude/projects/\(encoded)")
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","uuid":"fixture","timestamp":"2026-11-19T10:00:00.000Z","message":{"content":[{"type":"text","text":"Hello from Rex"}]}}"# + "\n"
        try Data(line.utf8).write(to: transcriptDirectory.appendingPathComponent("\(agentSession).jsonl"))

        // A Codex hook record proves the second Agent without a pid registry.
        let codexSplit = try await client.request("session.new_split", [
            "session_id": .string(sessionID),
            "anchor_id": .string(claudeBlock),
            "direction": .string("vertical"),
            "side": .string("after"),
            "focus": .bool(false),
            "layout": .object(["block": .object([
                "flavor": .string("com.superlogical.terminal.shell"),
                "options": .object([
                    "command": .array([.string(fakeCodex.path), .string("300")]),
                    "cwd": .string(project.path),
                    "interactive": .bool(false)
                ])
            ])])
        ])
        let codexBlock = try #require(codexSplit["block_ids"].array?.first?.string)
        for _ in 0..<40 {
            if let info = try? await client.request("com.superlogical.terminal.process", [
                "session_id": .string(sessionID), "block_id": .string(codexBlock), "args": .object([:])
            ]), (info["foreground"]["argv0"].string ?? info["foreground"]["name"].string) == "codex" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let codexSession = UUID().uuidString.lowercased()
        let codexTranscriptDirectory = home.appendingPathComponent(".codex/sessions/2026/11/19")
        try FileManager.default.createDirectory(at: codexTranscriptDirectory, withIntermediateDirectories: true)
        let codexTranscript = codexTranscriptDirectory.appendingPathComponent("rollout-\(codexSession).jsonl")
        let codexLine = #"{"type":"response_item","timestamp":"2026-11-19T10:00:00.000Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello from Codex"}]}}"# + "\n"
        try Data(codexLine.utf8).write(to: codexTranscript)
        let hookDirectory = root.appendingPathComponent("hooks")
        try RexHookWriter.write(RexHookRecord(agent: "codex", event: "Stop", sessionID: codexSession,
                                              transcript: codexTranscript.path, cwd: project.path,
                                              rexSession: sessionID, rexBlock: codexBlock, rexServer: nil),
                                directory: hookDirectory)

        let provider = RexProvider(endpoint: endpoint, label: "Rex fixture", mutations: MutationLedger())
        let source = RexConversationSource(provider: provider, home: home,
                                           transcriptRoots: [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex")],
                                           reader: TranscriptReader(), hookSpool: RexHookSpool(directory: hookDirectory))
        let rows = try await source.rows()
        let conversation = try #require(rows.first(where: { $0.descriptor.id == agentSession }))
        #expect(conversation.descriptor.agent == "claude")
        #expect(conversation.descriptor.cwd == project.path)
        #expect(conversation.descriptor.state == "idle")
        #expect(conversation.descriptor.workspaceID != nil)
        #expect(conversation.descriptor.surfaceID != nil)

        let history = try await source.history(agentSession, beforeSeq: nil, limit: 20)
        #expect(history.messages.contains { message in
            if case .prose(let prose) = message.kind { return prose.text.contains("Hello from Rex") }
            return false
        })
        let preview = try await source.preview(agentSession)
        #expect(preview.available)

        let codex = try #require(rows.first(where: { $0.descriptor.id == codexSession }))
        #expect(codex.descriptor.agent == "codex")
        #expect(codex.descriptor.state == "idle")
        #expect(codex.descriptor.workspaceID != nil)
        try await source.sendText(codexSession, text: "hello codex", authorize: {})

        // The same rows reach the existing phone routes through SessionService.
        let demoTranscript = home.appendingPathComponent(".claude/demo.jsonl")
        try Data().write(to: demoTranscript)
        let service = SessionService(cmux: DemoCmux(transcript: demoTranscript.path, project: project.path),
                                     home: home, transcriptRoots: [home.appendingPathComponent(".claude")],
                                     reader: TranscriptReader())
        await service.attachRex(source)
        let listed = try await service.sessions()
        #expect(listed.contains { $0.id == agentSession && $0.source == "rex" && $0.kind == "agent" })
        // Shell-only Rex blocks stay out of the phone's list until terminals stand on their own.
        #expect(!listed.contains { $0.kind == "terminal" })
        let withTerminals = RexConversationSource(provider: provider, home: home,
                                                  transcriptRoots: [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex")],
                                                  reader: TranscriptReader(), hookSpool: RexHookSpool(directory: hookDirectory),
                                                  showsUnboundTerminals: true)
        #expect(try await withTerminals.rows().contains { $0.descriptor.kind == "terminal" && $0.descriptor.source == "rex" })
        let serviceHistory = try await service.history(id: agentSession, beforeSeq: nil, limit: 20)
        #expect(serviceHistory.messages.contains { message in
            if case .prose(let prose) = message.kind { return prose.text.contains("Hello from Rex") }
            return false
        })
        let sent = try await service.send(id: agentSession, request: SendRequest(text: "hello", operationID: UUID()))
        #expect(sent.accepted)
        let interrupted = try await service.interrupt(id: agentSession, request: InterruptRequest(hard: false, operationID: UUID()))
        #expect(interrupted.accepted)

        _ = try? await client.request("session.destroy", ["session_id": .string(sessionID)])
        await provider.close()
        await client.close()
    }

    private static func rexExecutable() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", "command -v rex"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }
}
