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
    /// The byte offset of each line's first byte, in the order they were written.
    private func lineOffsets(_ lines: [Data]) -> [Int] {
        var offsets: [Int] = []; var running = 0
        for line in lines { offsets.append(running); running += line.count }
        return offsets
    }
    private func pageIDs(_ page: ConversationArchivePage) -> [String] {
        page.snapshot.messages.map(\.id)
    }

    /// Sequence numbers are the byte offset of the line that produced each message, so the same
    /// record read through a whole page and through a chain of small chunks reports the same seq.
    @Test func messagesCarryByteOffsetSequencesStableAcrossCursors() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let texts = (0..<60).map { index in
            "message \(index) " + String(repeating: "x", count: index % 3 == 0 ? 400 : 10)
        }
        let rows = try texts.enumerated().map { try userLine("m\($0.offset)", text: $0.element) }
        try write(rows, to: file)
        let offsets = lineOffsets(rows)
        let expectedIDs = (0..<60).map { "m\($0)" }

        // One call large enough to read the whole small record.
        let whole = try await TranscriptReader().archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 200)
        #expect(whole.complete)
        #expect(pageIDs(whole) == expectedIDs)
        #expect(whole.snapshot.messages.map(\.seq) == offsets)

        // The same record walked through 4 KiB chunks with a different page size.
        let chunked = TranscriptReader(chunkBytes: 4_096)
        var page = try await chunked.archive(path: file.path, agent: "claude", tail: 7, cursor: nil, limit: 200)
        var seen: [String: Int] = [:]
        for message in page.snapshot.messages { seen[message.id] = message.seq }
        while let cursor = page.nextCursor {
            #expect(!page.complete)
            page = try await chunked.archive(path: file.path, agent: "claude", tail: nil, cursor: cursor, limit: 9)
            for message in page.snapshot.messages { seen[message.id] = message.seq }
        }
        #expect(page.complete)
        #expect(seen.count == expectedIDs.count)
        for (index, id) in expectedIDs.enumerated() {
            #expect(seen[id] == offsets[index])
        }
    }

    /// Walking from the newest page down to `complete` visits every message once, in order, when
    /// the fixture mixes short and long records and the chunk size cuts through the file.
    @Test func walkingCursorsVisitsEveryMessageExactlyOnceInOrder() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let rows = try (0..<300).map { index in
            try userLine("m\(index)", text: "message \(index) " + String(repeating: "y", count: index % 5 == 0 ? 700 : 20))
        }
        try write(rows, to: file)
        let expected = (0..<300).map { "m\($0)" }
        let reader = TranscriptReader(chunkBytes: 4_096)

        var page = try await reader.archive(path: file.path, agent: "claude", tail: 11, cursor: nil, limit: 200)
        var collected = pageIDs(page)
        #expect(collected == Array(expected.suffix(11)))
        var previousFirstSeq = try #require(page.snapshot.messages.first?.seq)
        var iterations = 0
        while let cursor = page.nextCursor {
            #expect(!page.complete && page.snapshot.hasMore)
            page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: cursor, limit: 7)
            let ids = pageIDs(page)
            #expect(!ids.isEmpty)
            let firstSeq = try #require(page.snapshot.messages.first?.seq)
            // Every page moves strictly backwards, so a cursor can never loop.
            #expect(firstSeq < previousFirstSeq)
            previousFirstSeq = firstSeq
            collected = ids + collected
            iterations += 1
            #expect(iterations < 500)
        }
        #expect(page.complete && page.nextCursor == nil && !page.snapshot.hasMore)
        #expect(collected == expected)
        #expect(Set(collected).count == expected.count)
    }

    /// `complete` is true exactly on the page whose first returned line is byte zero.
    @Test func completeOnlyOnThePageThatReachesOffsetZero() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let rows = try (0..<25).map { try userLine("m\($0)", text: "message \($0)") }
        try write(rows, to: file)
        let reader = TranscriptReader(chunkBytes: 2_048)

        var page = try await reader.archive(path: file.path, agent: "claude", tail: 4, cursor: nil, limit: 3)
        var completePages = 0
        var visited: [String] = []
        while true {
            let ids = pageIDs(page)
            visited = ids + visited
            if page.complete {
                completePages += 1
                #expect(page.nextCursor == nil)
                #expect(page.snapshot.messages.first?.seq == 0)
                #expect(!page.snapshot.hasMore)
            } else {
                #expect(page.nextCursor != nil)
                #expect((page.snapshot.messages.first?.seq ?? -1) > 0)
                #expect(page.snapshot.hasMore)
            }
            guard let cursor = page.nextCursor else { break }
            page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: cursor, limit: 3)
        }
        #expect(completePages == 1)
        #expect(visited == (0..<25).map { "m\($0)" })
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

    @Test func countAndByteBoundsCutAPageShortAndTheNextCursorMakesProgress() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        try write(try (0..<30).map { try userLine("m\($0)", text: "message \($0)") }, to: file)
        let reader = TranscriptReader()

        var page = try await reader.archive(path: file.path, agent: "claude", tail: 10, cursor: nil, limit: 100)
        #expect(page.snapshot.messages.count == 10)
        #expect(!page.complete && page.snapshot.hasMore)
        let firstSeq = try #require(page.snapshot.messages.first?.seq)
        page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: page.nextCursor, limit: 10)
        #expect(page.snapshot.messages.count == 10)
        #expect(!page.complete)
        #expect((page.snapshot.messages.first?.seq ?? -1) < firstSeq)

        // 70 parsed bodies exceed the 1 MiB byte budget before the 200-message count budget.
        let large = root.appendingPathComponent("large.jsonl")
        try write(try (0..<70).map { try userLine("big\($0)", text: String(repeating: "z", count: 20_000)) }, to: large)
        var bytes = 0
        page = try await reader.archive(path: large.path, agent: "claude", tail: nil, cursor: nil, limit: 200)
        for message in page.snapshot.messages { bytes += (try JSONEncoder().encode(message)).count }
        #expect(page.snapshot.messages.count < 70)
        #expect(bytes <= 1_048_576)
        #expect(!page.complete)
        var seen = page.snapshot.messages.map(\.id)
        var cursorFirstSeq = try #require(page.snapshot.messages.first?.seq)
        while let cursor = page.nextCursor {
            page = try await reader.archive(path: large.path, agent: "claude", tail: nil, cursor: cursor, limit: 200)
            #expect((page.snapshot.messages.first?.seq ?? -1) < cursorFirstSeq)
            cursorFirstSeq = try #require(page.snapshot.messages.first?.seq)
            seen = page.snapshot.messages.map(\.id) + seen
        }
        #expect(page.complete)
        #expect(seen.count == 70)

        // The remaining `history_too_large` is reserved for an impossible configured chunk.
        do {
            _ = try await TranscriptReader(chunkBytes: 67_108_865)
                .archive(path: file.path, agent: "claude", tail: nil, cursor: nil, limit: 10)
            Issue.record("Expected an oversized chunk to be refused")
        } catch {
            #expect((error as? BridgeError)?.code == "history_too_large")
            #expect((error as? BridgeError)?.status == 413)
        }
    }

    /// A 12 MiB record is paged with a deliberately tiny chunk. Coherent, ordered, non-repeating
    /// pages show that each request stayed inside its bounded chunk instead of reading the record.
    @Test func bigFixtureIsPagedInTinyChunks() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("big.jsonl")
        var data = Data()
        var expected: [String] = []
        for index in 0..<21_000 {
            let line = try userLine("big\(index)", text: String(repeating: "b", count: 600) + " \(index)")
            data.append(line)
            expected.append("big\(index)")
        }
        #expect(data.count >= 12 * 1_048_576)
        try data.write(to: file)

        let reader = TranscriptReader(chunkBytes: 65_536)
        var page = try await reader.archive(path: file.path, agent: "claude", tail: 50, cursor: nil, limit: 200)
        var collected = pageIDs(page)
        var previousFirstSeq = try #require(page.snapshot.messages.first?.seq)
        var iterations = 0
        while let cursor = page.nextCursor {
            page = try await reader.archive(path: file.path, agent: "claude", tail: nil, cursor: cursor, limit: 200)
            let messages = page.snapshot.messages
            #expect(!messages.isEmpty)
            #expect(messages.count <= 200)
            // Sequence numbers are line byte offsets, so they rise within a page.
            #expect(zip(messages, messages.dropFirst()).allSatisfy { $0.0.seq < $0.1.seq })
            let firstSeq = try #require(messages.first?.seq)
            #expect(firstSeq < previousFirstSeq)
            previousFirstSeq = firstSeq
            collected = messages.map(\.id) + collected
            iterations += 1
            #expect(iterations < 2_000)
        }
        #expect(page.complete)
        #expect(collected.count == expected.count)
        #expect(collected == expected)
        // A page that walked the whole record cannot have been produced by one whole-file read.
        #expect(iterations > 4)
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
        // History keeps line-index sequence numbers; the archive's byte-offset rewrite does not leak.
        #expect(after.messages.map(\.seq) == Array(0..<after.messages.count))
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
