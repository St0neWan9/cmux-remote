import Foundation
import Testing
@testable import CmuxRemoteBridge
import CmuxRemoteCore

@Suite struct ConversationArchiveTests {
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-archive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func userLine(_ id: String, text: String) throws -> Data {
        let row: [String: Any] = ["type": "user", "uuid": id, "message": ["content": text]]
        var data = try JSONSerialization.data(withJSONObject: row); data.append(10); return data
    }
    private func write(_ lines: [Data], to file: URL) throws {
        try lines.reduce(into: Data()) { $0.append($1) }.write(to: file)
    }

    /// A clipped history window must not renumber the archive: sequence numbers stay absolute line
    /// indexes, including when a 1 MiB chunk boundary falls inside a record.
    @Test func absoluteSequenceNumbersSurviveWindowsAndChunkBoundaries() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let rows = try (0..<12).map { try userLine("m\($0)", text: String(repeating: "x", count: 120_000)) }
        try write(rows, to: file)
        let reader = TranscriptReader(windowLimit: 4_096, windowStep: 1_024)
        let window = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 200)
        #expect(window.clipped)
        #expect(!window.messages.contains { $0.id == "m0" })

        let archive = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 200)
        #expect(archive.complete)
        #expect(archive.snapshot.messages.map(\.seq) == Array(0..<12))
        #expect(archive.snapshot.messages.map(\.id) == (0..<12).map { "m\($0)" })
        #expect(archive.snapshot.clipped == false)
    }

    /// Two readers built over the same state directory answer with one generation; truncating the
    /// record replaces it. The state file is owner-only.
    @Test func generationSurvivesRestartAndChangesOnTruncation() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state")
        let file = root.appendingPathComponent("chat.jsonl")
        let rows = try (0..<6).map { try userLine("m\($0)", text: "message \($0)") }
        try write(rows, to: file)

        let first = try await TranscriptReader(generationStore: TranscriptGenerationStore(directory: state))
            .archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 100)
        let restartedReader = TranscriptReader(generationStore: TranscriptGenerationStore(directory: state))
        let second = try await restartedReader.archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 100)
        #expect(first.snapshot.generation == second.snapshot.generation)

        let stateFile = state.appendingPathComponent("transcript-generations.json")
        let permissions = try #require(FileManager.default.attributesOfItem(atPath: stateFile.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)

        try userLine("short", text: "only this").write(to: file)
        let truncated = try await restartedReader.archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 100)
        #expect(truncated.snapshot.generation != first.snapshot.generation)
        #expect(truncated.snapshot.messages.map(\.id) == ["short"])
    }

    @Test func cursorsRoundTripAndAStaleGenerationIsRefused() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state")
        let file = root.appendingPathComponent("chat.jsonl")
        try write(try (0..<20).map { try userLine("m\($0)", text: "message \($0)") }, to: file)
        let reader = TranscriptReader(generationStore: TranscriptGenerationStore(directory: state))

        var page = try await reader.archive(path: file.path, agent: "claude", tail: 5, cursor: nil, limit: 100)
        #expect(page.snapshot.messages.map(\.id) == ["m15", "m16", "m17", "m18", "m19"])
        #expect(!page.complete)
        var collected = page.snapshot.messages.map(\.id)
        while let cursor = page.nextCursor {
            #expect(!page.complete)
            page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: cursor, limit: 5)
            collected = page.snapshot.messages.map(\.id) + collected
        }
        #expect(page.complete)
        #expect(collected == (0..<20).map { "m\($0)" })

        // Keep the old cursor, then shrink the record: the generation is replaced and the cursor is
        // no longer allowed to continue from records it did not describe.
        let stale = try await reader.archive(path: file.path, agent: "claude", tail: 5, cursor: nil, limit: 5).nextCursor
        try write(try (0..<3).map { try userLine("n\($0)", text: "new \($0)") }, to: file)
        do {
            _ = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: stale, limit: 5)
            Issue.record("Expected a stale cursor refusal")
        } catch {
            #expect((error as? BridgeError)?.code == "history_cursor_stale")
            #expect((error as? BridgeError)?.status == 409)
        }
    }

    @Test func pagesAreBoundedByCountAndBytesAndCompleteOnlyAtTheFirstRecord() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        try write(try (0..<30).map { try userLine("m\($0)", text: "message \($0)") }, to: file)
        let reader = TranscriptReader()

        var page = try await reader.archive(path: file.path, agent: "claude", tail: 10, cursor: nil, limit: 100)
        #expect(page.snapshot.messages.count == 10)
        #expect(!page.complete && page.snapshot.hasMore)
        page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: page.nextCursor, limit: 10)
        #expect(page.snapshot.messages.count == 10)
        #expect(!page.complete)
        page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: page.nextCursor, limit: 10)
        #expect(page.snapshot.messages.count == 10)
        #expect(page.complete && !page.snapshot.hasMore && page.nextCursor == nil)
        #expect(page.snapshot.messages.first?.seq == 0)

        // 70 parsed bodies exceed the 1 MiB byte budget before the 200-message count budget.
        let large = root.appendingPathComponent("large.jsonl")
        try write(try (0..<70).map { try userLine("big\($0)", text: String(repeating: "y", count: 20_000)) }, to: large)
        var bytes = 0
        page = try await reader.archive(path: large.path, agent: "claude", tail: nil, cursor: nil, limit: 200)
        for message in page.snapshot.messages { bytes += (try JSONEncoder().encode(message)).count }
        #expect(page.snapshot.messages.count < 70)
        #expect(bytes <= 1_048_576)
        #expect(!page.complete)
        var seen = page.snapshot.messages.map(\.id)
        while let cursor = page.nextCursor {
            page = try await reader.archive(path: large.path, agent: "claude", tail: nil, cursor: cursor, limit: 200)
            seen += page.snapshot.messages.map(\.id)
        }
        #expect(page.complete)
        #expect(seen.count == 70)
    }

    @Test func recordsOverTheCompleteLimitsAnswerHistoryTooLarge() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        try write(try (0..<6).map { try userLine("m\($0)", text: String(repeating: "z", count: 512)) }, to: file)

        let bytesLimited = TranscriptReader(completeLimit: 1_024)
        do {
            _ = try await bytesLimited.archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 100)
            Issue.record("Expected the byte limit to refuse the archive")
        } catch {
            #expect((error as? BridgeError)?.code == "history_too_large")
            #expect((error as? BridgeError)?.status == 413)
        }
        // The small complete limit must not change the bounded history route.
        #expect(try await bytesLimited.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100).messages.count == 6)

        let messagesLimited = TranscriptReader(completeMessageLimit: 4)
        do {
            _ = try await messagesLimited.archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 100)
            Issue.record("Expected the message limit to refuse the archive")
        } catch {
            #expect((error as? BridgeError)?.code == "history_too_large")
            #expect((error as? BridgeError)?.status == 413)
        }
    }

    @Test func archiveReadsDoNotChangeLegacyHistoryOutput() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let rows: [[String: Any]] = [
            ["type": "user", "uuid": "u1", "timestamp": "2026-10-24T10:00:00.000Z", "message": ["content": "Run it"]],
            ["type": "assistant", "uuid": "a1", "timestamp": "2026-10-24T10:00:01.000Z", "message": ["content": [["type": "tool_use", "id": "tool1", "name": "Read", "input": ["file_path": "/project/README.md"]]]]],
            ["type": "user", "uuid": "r1", "timestamp": "2026-10-24T10:00:02.000Z", "message": ["content": [["type": "tool_result", "tool_use_id": "tool1", "content": "README text"]]]],
            ["type": "system", "uuid": "s1", "subtype": "turn_duration", "timestamp": "2026-10-24T10:00:09.000Z", "durationMs": 8000]
        ]
        try write(try rows.map { var data = try JSONSerialization.data(withJSONObject: $0); data.append(10); return data }, to: file)
        let reader = TranscriptReader()
        let before = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        _ = try await reader.archive(path: file.path, agent: "claude", tail: 3, cursor: nil, limit: 100)
        let after = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(before) == encoder.encode(after))
        #expect(before.generation == after.generation)
    }

    /// A tool record and its image that the bounded window no longer holds resolve through the
    /// archive generation, including after a simulated Bridge restart.
    @Test func oldToolDetailAndImageResolveThroughTheArchiveObservation() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state")
        let file = root.appendingPathComponent("chat.jsonl")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
        var rows: [[String: Any]] = [
            ["type": "assistant", "uuid": "old-call", "message": ["content": [["type": "tool_use", "id": "tool-old", "name": "Read", "input": ["file_path": "/outside/photo.png"]]]]],
            ["type": "user", "uuid": "old-result", "message": ["content": [["type": "tool_result", "tool_use_id": "tool-old", "content": [["type": "text", "text": "OLD OUTPUT DETAIL"], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]]]]]]
        ]
        rows += (0..<20).map { index -> [String: Any] in
            ["type": "user", "uuid": "filler\(index)", "message": ["content": "filler message \(index) " + String(repeating: "f", count: 120)]]
        }
        try write(try rows.map { var data = try JSONSerialization.data(withJSONObject: $0); data.append(10); return data }, to: file)

        let reader = TranscriptReader(windowLimit: 600, windowStep: 100,
                                      generationStore: TranscriptGenerationStore(directory: state))
        let window = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(window.clipped)
        #expect(!window.messages.contains { $0.id == "old-call" })

        let archive = try await reader.archive(path: file.path, agent: "claude", tail: 200, cursor: nil, limit: 200)
        #expect(archive.snapshot.messages.contains { $0.id == "old-call" })
        let reference = try #require(archive.snapshot.images?.first { !$0.requiresProjectRead })
        #expect(reference.messageID == "old-call")
        let image = try await reader.image(path: file.path, agent: "claude", referenceID: reference.id, generation: archive.snapshot.generation)
        if case .recorded(let bytes) = image.source { #expect(bytes == png) } else { Issue.record("Expected recorded image bytes") }
        let detail = try await reader.toolText(path: file.path, agent: "claude", messageID: "old-call", generation: archive.snapshot.generation,
                                               field: "output", offset: 0, contentID: nil, limit: 16_384)
        #expect(detail.text == "OLD OUTPUT DETAIL")

        // A restarted Bridge loads the same generation from its state directory and rebuilds the
        // complete observation when the detail is opened.
        let restarted = TranscriptReader(windowLimit: 600, windowStep: 100,
                                         generationStore: TranscriptGenerationStore(directory: state))
        let restartedImage = try await restarted.image(path: file.path, agent: "claude", referenceID: reference.id, generation: archive.snapshot.generation)
        if case .recorded(let bytes) = restartedImage.source { #expect(bytes == png) } else { Issue.record("Expected recorded image bytes after restart") }
        let restartedDetail = try await restarted.toolText(path: file.path, agent: "claude", messageID: "old-call", generation: archive.snapshot.generation,
                                                           field: "output", offset: 0, contentID: nil, limit: 16_384)
        #expect(restartedDetail.text == "OLD OUTPUT DETAIL")
    }

    @Test func routeServesArchivePagesAndRequiresConversationRead() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.jsonl")
        try write(try (0..<5).map { try userLine("m\($0)", text: "message \($0)") }, to: file)
        let service = SessionService(cmux: DemoCmux(transcript: file.path, project: root.path), home: root, transcriptRoots: [root],
                                     reader: TranscriptReader(generationStore: TranscriptGenerationStore(directory: root.appendingPathComponent("state"))))
        let router = BridgeRouter(service: service, token: "fixture-token")
        let uri = "/v1/sessions/demo-session/archive?tail=2"
        let unauthorized = await router.respond(method: "GET", uri: uri, authorization: nil, body: Data())
        #expect(unauthorized.0 == 401)
        let success = await router.respond(method: "GET", uri: uri, authorization: "Bearer fixture-token", body: Data())
        #expect(success.0 == 200)
        let page = try JSONDecoder().decode(ConversationArchivePage.self, from: success.1)
        #expect(page.snapshot.messages.map(\.id) == ["m3", "m4"])
        #expect(!page.complete)
        let cursor = try #require(page.nextCursor)
        let older = await router.respond(method: "GET", uri: "/v1/sessions/demo-session/archive?cursor=\(cursor)&limit=2", authorization: "Bearer fixture-token", body: Data())
        #expect(older.0 == 200)
        #expect(try JSONDecoder().decode(ConversationArchivePage.self, from: older.1).snapshot.messages.map(\.id) == ["m1", "m2"])
    }
}
