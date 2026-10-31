import Foundation
import CmuxRemoteCore
import CmuxAgentChat

/// Reads complete, bounded JSONL records; partial trailing lines are not committed.
public actor TranscriptReader {
    private struct Observation {
        let inode: String
        let size: Int
        let modified: Date?
        let generation: UUID
        let windowStart: Int
        let images: [TranscriptImageRecord]
        let messages: [ChatMessage]
        let presentation: TranscriptResponseReader.Result
        let agentModel: AgentModelState?
        /// The first byte after the last complete record parsed, so an appended chunk resumes here.
        let parsedThrough: Int
        /// The highest record number parsed; the next record continues from it.
        let lastSeq: Int
        /// The turn fold, carried so an open turn continues across chunks.
        let responseState: TranscriptResponseReader.State
        /// The detached-call scan, carried so earlier launches stay paired with later completions.
        let trackerState: BackgroundTaskTracker.State
        /// The newest records, so a tool call and its result pair across a chunk edge.
        let tailLines: [String]
    }
    private var observations: [String: Observation] = [:]
    /// Last-read order per path; an eviction takes the lowest, which is the least recently read.
    private var observationOrder: [String: Int] = [:]
    private var observationSequence = 0
    /// Long conversations are read from a bounded tail; the window start moves in whole steps so sequence numbers stay stable while the file grows.
    private let windowLimit: Int
    private let windowStep: Int
    /// The archive reads one bounded byte window ending at the requested offset instead of the whole
    /// record, so a large transcript costs a chunk rather than minutes.
    private let archiveChunkBytes: Int
    /// A stable generation per transcript path, so an archive cursor survives a Bridge restart.
    private let generationStore: TranscriptGenerationStore
    private static let archivePageCountLimit = 200
    private static let archivePageByteLimit = 1_048_576
    private static let archiveChunkCeiling = 67_108_864
    /// Detached calls per transcript. Tasks outlive the turn that started them, so they are kept beside the
    /// messages; keyed by path, because one reader serves every conversation and an unchanged record is
    /// answered from this cache.
    private var launches: [String: [BackgroundTaskTracker.Launch]] = [:]
    private static let capacity = 32
    /// How long a retried background agent's own record counts as proof that it is running again.
    private static let resumeWindow: TimeInterval = 900
    /// A Monitor's deadline passes while its record stays unchanged, so running is decided at read time.
    private let now: @Sendable () -> Date
    public init(windowLimit: Int = 33_554_432, windowStep: Int = 8_388_608, now: @escaping @Sendable () -> Date = { Date() },
                generationStore: TranscriptGenerationStore = TranscriptGenerationStore(directory: nil),
                chunkBytes: Int = 8_388_608) {
        self.windowLimit = max(1, windowLimit); self.windowStep = max(1, min(windowStep, windowLimit)); self.now = now
        self.generationStore = generationStore; self.archiveChunkBytes = max(1, chunkBytes)
    }

    /// A cheap identity of the record a read of this path would answer from, or nil when unprovable.
    ///
    /// Two equal stamps mean a repeated read answers from the same cached record with the same running
    /// tasks, so a subscription may skip it. Read from file metadata alone: no file read, no parse. Nil
    /// — do the work — when the record is not cached, the file no longer matches it, or the metadata
    /// cannot be read.
    public func stamp(path: String) -> String? {
        guard let cached = observations[path],
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let inode = "\(attributes[.systemFileNumber] ?? "unknown")"
        guard cached.inode == inode, cached.size == size, cached.modified == modified else { return nil }
        // A Monitor's deadline changes the answer while the file stays still, and so does a retried agent
        // whose sidecar record came back to life.
        let moment = now()
        let running = runningTasks(path: path, at: moment).count
        return "\(cached.generation.uuidString):\(inode):\(size):\(modified.timeIntervalSinceReferenceDate):\(running)"
    }

    /// A subagent record shares the main record's shape but marks every row `isSidechain`; the pinned parser drops
    /// those rows, so a subagent's own conversation is read with the mark removed first.
    private static func withoutSidechain(_ lines: [String]) -> [String] {
        lines.map { line in
            guard line.contains("\"isSidechain\"") else { return line }
            guard let data = line.data(using: .utf8),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object.removeValue(forKey: "isSidechain") != nil,
                  let encoded = try? JSONSerialization.data(withJSONObject: object),
                  let text = String(data: encoded, encoding: .utf8) else { return line }
            return text
        }
    }
    private func touch(_ path: String) {
        observationSequence += 1; observationOrder[path] = observationSequence
    }
    /// Evicts the least recently read record, one per insertion, instead of the whole cache: a burst of
    /// new paths used to guarantee a full re-parse of every conversation still open. A record and its
    /// launches leave together, so a cached record never answers without its running tasks.
    private func store(_ observation: Observation, for path: String) {
        if observations[path] == nil, observations.count >= Self.capacity,
           let oldest = observationOrder.min(by: { $0.value < $1.value })?.key {
            observations[oldest] = nil; launches[oldest] = nil; observationOrder[oldest] = nil
        }
        observations[path] = observation
        launches[path] = observation.trackerState.launched.values.sorted { $0.task.id < $1.task.id }
        touch(path)
    }
    /// Where a read of this size starts: the newest bytes within the window, in whole steps so record
    /// numbers stay put while the file grows.
    private func windowStart(size: Int) -> Int {
        size > windowLimit ? (size - windowLimit + windowStep - 1) / windowStep * windowStep : 0
    }
    /// The newest complete lines of a transcript within the read window, where that window starts, and the
    /// absolute offset of the returned data's first byte.
    private func window(path: String, size: Int) throws -> (data: Data, start: Int, offset: Int) {
        let start = windowStart(size: size)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
        // One byte before the window shows whether it begins on a line boundary.
        let readStart = max(0, start - 1)
        try handle.seek(toOffset: UInt64(readStart))
        var data = Data()
        while data.count < size - readStart, let chunk = try handle.read(upToCount: min(1_048_576, size - readStart - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
        }
        guard start > 0 else { return (data, 0, 0) }
        // A record cut by the window start is never parsed.
        guard let firstBreak = data.firstIndex(of: 10) else { return (Data(), start, start) }
        let offset = start + data.distance(from: data.startIndex, to: firstBreak)
        return (Data(data[data.index(after: firstBreak)...]), start, offset)
    }
    /// - Parameter reportsBackgroundTasks: Whether the agent process that owns this record is still running.
    ///   Its detached tasks die with it, so an ended session reports none, whatever its record says.
    public func history(path: String, agent: String, beforeSeq: Int?, limit: Int, allowsUncreatedTranscript: Bool = false,
                        reportsBackgroundTasks: Bool = true, includesSidechain: Bool = false) throws -> ConversationSnapshot {
        // One record read two ways keeps two cached records; the phone asks for a subagent only by its own file.
        let path = includesSidechain ? path + "\u{0}sidechain" : path
        let file = includesSidechain ? String(path.dropLast("\u{0}sidechain".count)) : path
        let url = URL(fileURLWithPath: file)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file) }
        catch {
            let failure = error as NSError
            // A newly bound agent may not create its JSONL until the first prompt.
            // Never turn a deleted, previously read transcript into an empty history.
            guard allowsUncreatedTranscript, observations[path] == nil,
                  failure.domain == NSCocoaErrorDomain,
                  [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(failure.code) else { throw error }
            let generation = "pending:" + IdentityCryptography().digest(Data(path.utf8))
            return ConversationSnapshot(messages: [], hasMore: false, generation: generation, clipped: false)
        }
        guard let size = attributes[.size] as? NSNumber else { throw BridgeError("history_unavailable", "The conversation record size is unavailable.", status: 404) }
        let inode = "\(attributes[.systemFileNumber] ?? "unknown")"
        let modified = attributes[.modificationDate] as? Date
        let previous = observations[path]
        if let previous, previous.inode == inode, previous.size == size.intValue, previous.modified == modified {
            touch(path)
            return page(previous.messages, images: previous.images, presentation: previous.presentation, beforeSeq: beforeSeq, limit: limit, generation: previous.generation, clipped: previous.windowStart > 0,
                        backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks), agentModel: previous.agentModel)
        }
        let windowStart = windowStart(size: size.intValue)
        // A record that only grew is read from where the last read stopped; parsing the whole window again
        // would cost as much as the file, which is what made a busy conversation slow to reach the phone.
        if let previous, previous.inode == inode, size.intValue > previous.size, previous.windowStart == windowStart,
           previous.parsedThrough >= previous.windowStart, previous.parsedThrough <= size.intValue,
           let appended = try append(path: file, agent: agent, previous: previous, through: size.intValue, modified: modified, includesSidechain: includesSidechain, key: path) {
            touch(path)
            return page(appended.messages, images: appended.images, presentation: appended.presentation, beforeSeq: beforeSeq, limit: limit, generation: previous.generation, clipped: windowStart > 0,
                        backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks), agentModel: appended.agentModel)
        }
        let (data, resolvedStart, dataOffset) = try window(path: file, size: size.intValue)
        // Cheap line scan over the same window the parse reads; a launch and its completion can sit far apart.
        let scanned = scannedLaunches(data)
        // A moved window renumbers records, so clients re-anchor exactly as after truncation.
        let reset = previous == nil || previous?.inode != inode || size.intValue < (previous?.size ?? 0) || previous?.windowStart != resolvedStart
        let generation = reset ? UUID() : previous!.generation
        guard let end = data.lastIndex(of: 10) else {
            store(Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: resolvedStart, images: [], messages: [], presentation: .init(), agentModel: nil,
                              parsedThrough: dataOffset + data.count, lastSeq: -1, responseState: .init(), trackerState: scanned, tailLines: []), for: path)
            return page([], images: [], presentation: .init(), beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: resolvedStart > 0,
                        backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks))
        }
        let decoded = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let raw = includesSidechain ? Self.withoutSidechain(decoded) : decoded
        // Read before normalization, which folds away the command output that records a Claude switch.
        let agentModel = TranscriptModelReader().read(lines: raw, agent: agent)
        let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw) : .init(lines: raw, markers: [])
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
        let result = agent == "claude" ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: 0) : CodexTranscriptParser().parse(lines: lines, startingSeq: 0)
        // A record may repeat an id as it develops; one index by id beats a scan per update.
        var positions: [String: Int] = [:]
        for (index, message) in result.messages.enumerated() where positions[message.id] == nil { positions[message.id] = index }
        var messages = result.messages
        for update in result.updatedMessages {
            if let index = positions[update.id] { messages[index] = update }
        }
        let imageIndex = try TranscriptImageIndex().read(lines: lines, messages: messages, agent: agent)
        messages.append(contentsOf: imageIndex.supplementalMessages + compaction.markers); messages.sort { $0.seq < $1.seq }
        var responseState = TranscriptResponseReader.State()
        TranscriptResponseReader().consume(lines: lines, startingSeq: 0, messages: messages, agent: agent, into: &responseState)
        let presentation = TranscriptResponseReader().snapshot(responseState)
        store(Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: resolvedStart, images: imageIndex.records, messages: messages, presentation: presentation, agentModel: agentModel,
                          parsedThrough: dataOffset + end + 1, lastSeq: lines.count - 1, responseState: responseState, trackerState: scanned, tailLines: Array(lines.suffix(64))), for: path)
        return page(messages, images: imageIndex.records, presentation: presentation, beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: resolvedStart > 0,
                    backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks), agentModel: agentModel)
    }
    /// Parses only the records appended since the previous read, carrying the fold state forward.
    /// Returns nil when nothing complete was appended, so the caller answers from the cached record.
    private func append(path: String, agent: String, previous: Observation, through size: Int, modified: Date?, includesSidechain: Bool, key: String) throws -> Observation? {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(previous.parsedThrough))
        var chunk = Data()
        while chunk.count < size - previous.parsedThrough,
              let part = try handle.read(upToCount: min(1_048_576, size - previous.parsedThrough - chunk.count)), !part.isEmpty {
            try Task.checkCancellation(); chunk.append(part)
        }
        guard let end = chunk.lastIndex(of: 10) else { return nil }
        let complete = Data(chunk[...end])
        let decoded = String(decoding: complete, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let raw = includesSidechain ? Self.withoutSidechain(decoded) : decoded
        guard !raw.isEmpty else { return nil }
        let startingSeq = previous.lastSeq + 1
        var tracker = previous.trackerState
        BackgroundTaskTracker().consume(raw, into: &tracker)
        let agentModel = TranscriptModelReader().read(lines: raw, agent: agent) ?? previous.agentModel
        let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw, startingSeq: startingSeq) : .init(lines: raw, markers: [])
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
        let result = agent == "claude" ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: startingSeq) : CodexTranscriptParser().parse(lines: lines, startingSeq: startingSeq)
        var positions: [String: Int] = [:]
        for (index, message) in previous.messages.enumerated() where positions[message.id] == nil { positions[message.id] = index }
        var messages = previous.messages
        for update in result.updatedMessages {
            if let index = positions[update.id] { messages[index] = update }
        }
        for message in result.messages where positions[message.id] == nil {
            positions[message.id] = messages.count; messages.append(message)
        }
        // An image pairs a tool call with its result; the edge between two reads can fall between them.
        let context = Array(previous.tailLines.suffix(64))
        let contextStart = startingSeq - context.count
        let combined = context + lines
        let contextMessages = messages.filter { $0.seq >= contextStart }
        let imageIndex = try TranscriptImageIndex().read(lines: combined, messages: contextMessages, agent: agent, startingSeq: contextStart)
        var images = previous.images
        var imageIDs = Set(images.map { $0.reference(generation: "deduplicate").id })
        for record in imageIndex.records { let id = record.reference(generation: "deduplicate").id; if imageIDs.insert(id).inserted { images.append(record) } }
        for message in imageIndex.supplementalMessages + compaction.markers where positions[message.id] == nil {
            positions[message.id] = messages.count; messages.append(message)
        }
        messages.sort { $0.seq < $1.seq }
        var responseState = previous.responseState
        TranscriptResponseReader().consume(lines: lines, startingSeq: startingSeq, messages: messages.filter { $0.seq >= startingSeq }, agent: agent, into: &responseState)
        let presentation = TranscriptResponseReader().snapshot(responseState)
        let observation = Observation(inode: previous.inode, size: size, modified: modified, generation: previous.generation, windowStart: previous.windowStart,
                                      images: Array(images.suffix(512)), messages: messages, presentation: presentation, agentModel: agentModel,
                                      parsedThrough: previous.parsedThrough + complete.count, lastSeq: startingSeq + lines.count - 1,
                                      responseState: responseState, trackerState: tracker, tailLines: Array(lines.suffix(64)))
        store(observation, for: key)
        return observation
    }
    /// The detached calls still open in one window, paired from launches, stops and completion notices.
    private func scannedLaunches(_ data: Data) -> BackgroundTaskTracker.State {
        var state = BackgroundTaskTracker.State()
        guard let end = data.lastIndex(of: 10) else { return state }
        let lines = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        BackgroundTaskTracker().consume(lines, into: &state)
        return state
    }
    /// This record's tasks still running now; none once the agent that owned them has ended.
    private func runningTasks(_ path: String, reports: Bool) -> [BackgroundAgentTask] {
        guard reports else { return [] }
        return runningTasks(path: path, at: now())
    }
    /// Every detached task the record leaves in flight: launches no notice ended, plus failures the agent
    /// has retried.
    private func runningTasks(path: String, at moment: Date) -> [BackgroundAgentTask] {
        var tasks = (launches[path] ?? []).filter { $0.isRunning(at: moment) }.map(\.task)
        if let state = observations[path]?.trackerState {
            for task in resumedTasks(path: path, state: state, at: moment) where !tasks.contains(where: { $0.id == task.id }) {
                tasks.append(task)
            }
        }
        return tasks.sorted { $0.id < $1.id }
    }
    /// Background agents a failure notice ended that are writing their own record again.
    ///
    /// Claude Code retries an agent that died on an API error without appending a new launch row, so the
    /// conversation still ends at the failure and the phone would hide a task the TUI shows running. The
    /// retry keeps writing `subagents/agent-<taskID>.jsonl` beside the session, and a record touched after
    /// the notice is the only evidence it left.
    private func resumedTasks(path: String, state: BackgroundTaskTracker.State, at moment: Date) -> [BackgroundAgentTask] {
        let file = path.hasSuffix("\u{0}sidechain") ? String(path.dropLast("\u{0}sidechain".count)) : path
        let session = URL(fileURLWithPath: file).deletingPathExtension()
        var tasks: [BackgroundAgentTask] = []
        for (toolUseID, settled) in state.failed {
            guard let taskID = state.taskIDByToolUse[toolUseID] else { continue }
            let record = session.appendingPathComponent("subagents/agent-\(taskID).jsonl").path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: record),
                  let modified = attributes[.modificationDate] as? Date else { continue }
            // A record written at failure time is the task that just died, not a retry.
            if let at = settled.at, modified <= at.addingTimeInterval(1) { continue }
            guard moment.timeIntervalSince(modified) < Self.resumeWindow else { continue }
            tasks.append(settled.launch.task)
        }
        return tasks
    }
    /// Read a tool's complete supported text without inflating ordinary history snapshots.
    public func toolText(path: String, agent: String, messageID: String, generation: String,
                         field: String, offset: Int, contentID: String?, limit: Int) async throws -> ToolTextPage {
        try Task.checkCancellation()
        let snapshot = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        let selectedGeneration = generation == "current" && offset == 0 && contentID == nil ? snapshot.generation : generation
        guard snapshot.generation == selectedGeneration else { throw BridgeError("stale_detail", "The conversation record changed. Reload this detail.", status: 409) }
        guard observations[path]?.messages.contains(where: { $0.id == messageID }) == true else { throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404) }
        guard let observed = observations[path] else { throw BridgeError("stale_detail", "The conversation record changed. Reload this detail.", status: 409) }
        // The same window as the snapshot keeps message identities aligned.
        let data = try window(path: path, size: observed.size).data
        guard let end = data.lastIndex(of: 10) else { throw BridgeError("detail_not_found", "No complete tool record is available.", status: 404) }
        let raw = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(ClaudeCompactionSummary().replace(raw).lines)) : raw
        try Task.checkCancellation()
        let result = agent == "claude"
            ? ClaudeTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: 0)
            : CodexTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: 0)
        guard let message = (result.updatedMessages + result.messages).first(where: { $0.id == messageID }) else { throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404) }
        let text: String
        switch (message.kind, field) {
        case (.toolUse(let tool), "input"): text = tool.inputDetail ?? ""
        case (.toolUse(let tool), "output"): text = tool.output ?? ""
        case (.terminal(let tool), "input"): text = tool.command
        case (.terminal(let tool), "output"): text = tool.output ?? ""
        case (.fileEdit(let tool), "diff"): text = tool.unifiedDiff ?? ""
        default: throw BridgeError("invalid_input", "Select a supported field of a tool record.", status: 422)
        }
        let refreshed = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        guard refreshed.generation == selectedGeneration else { throw BridgeError("stale_detail", "The conversation record changed during this read.", status: 409) }
        let digest = IdentityCryptography().digest(Data(text.utf8))
        guard contentID == nil || contentID == digest else { throw BridgeError("stale_detail", "The tool output changed. Reload this detail.", status: 409) }
        try Task.checkCancellation()
        let total = text.unicodeScalars.count
        guard offset >= 0, offset <= total else { throw BridgeError("invalid_input", "The text page offset is invalid.", status: 422) }
        let pageText = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(offset).prefix(min(16_384, max(1, limit)))))
        let next = offset + pageText.unicodeScalars.count
        return ToolTextPage(messageID: messageID, generation: selectedGeneration, field: field, contentID: digest,
                            text: pageText, offset: offset, nextOffset: next < total ? next : nil, totalCharacters: total)
    }

    func image(path: String, agent: String, referenceID: String, generation: String) async throws -> TranscriptImageRecord {
        let current = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        guard current.generation == generation else { throw BridgeError("stale_detail", "The image record changed. Reload the conversation.", status: 409) }
        guard let record = observations[path]?.images.first(where: { $0.reference(generation: generation).id == referenceID }) else { throw BridgeError("image_unavailable", "This recorded image is unavailable.", status: 404) }
        return record
    }

    // MARK: - Paged archive

    private struct ArchiveMetadata {
        let inode: String
        let creationDate: Date?
        let size: Int
    }
    private struct ArchiveCursor: Codable {
        let g: String
        let s: Int
    }
    /// The complete lines of one bounded read, with the file byte offset of each line.
    private struct ArchiveChunk {
        let lines: [String]
        let lineOffsets: [Int]
        /// Where the first complete line of the chunk begins, used when the chunk holds no messages.
        let firstLineOffset: Int
    }
    private func archiveMetadata(_ path: String) throws -> ArchiveMetadata {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = (attributes[.size] as? NSNumber)?.intValue else {
                throw BridgeError("history_unavailable", "The conversation record size is unavailable.", status: 404)
            }
            return ArchiveMetadata(inode: "\(attributes[.systemFileNumber] ?? "unknown")",
                                   creationDate: attributes[.creationDate] as? Date, size: size)
        } catch let error as BridgeError { throw error }
        catch { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
    }
    /// The newest `tail` messages, or the page before the byte offset named by an opaque cursor.
    ///
    /// Only `[end - chunkBytes, end)` is read and parsed. Sequence numbers are the file byte offset of
    /// the line that produced each message, so they stay stable and monotonic without walking the
    /// record from its first byte. A page carries at most 200 messages and about 1 MiB of encoded
    /// messages; a line's messages are never split.
    public func archive(path: String, agent: String, tail: Int?, cursor: String?, limit: Int,
                        reportsBackgroundTasks: Bool = true) async throws -> ConversationArchivePage {
        try Task.checkCancellation()
        guard archiveChunkBytes <= Self.archiveChunkCeiling else { throw archiveTooLarge() }
        let metadata = try archiveMetadata(path)
        let generation = await generationStore.generation(for: path, inode: metadata.inode,
                                                          creationDate: metadata.creationDate, size: metadata.size)
        let end: Int
        let count: Int
        if let cursor {
            let payload = try decodeArchiveCursor(cursor)
            guard payload.g == generation else {
                throw BridgeError("history_cursor_stale", "This archive cursor belongs to a different conversation record. Reload the archive.", status: 409)
            }
            // A cursor from this generation can only name a byte inside the record it described.
            end = min(payload.s, metadata.size)
            count = min(max(limit, 1), Self.archivePageCountLimit)
        } else {
            end = metadata.size
            count = min(max(tail ?? limit, 1), Self.archivePageCountLimit)
        }
        let start = max(0, end - archiveChunkBytes)
        let chunk = try readArchiveChunk(path: path, start: start, end: end)
        try Task.checkCancellation()
        return try archivePage(chunk: chunk, chunkStart: start, count: count, generation: generation,
                               agent: agent, newest: cursor == nil, reportsBackgroundTasks: reportsBackgroundTasks)
    }
    /// One bounded read. Cancellation is checked before and during the read, so a request abandoned
    /// while a large chunk is in flight releases the record immediately.
    private func readArchiveChunk(path: String, start: Int, end: Int) throws -> Data {
        guard end > start else { return Data() }
        try Task.checkCancellation()
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)) }
        catch { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(start))
        let total = end - start
        var data = Data()
        while data.count < total {
            try Task.checkCancellation()
            guard let part = try handle.read(upToCount: min(1_048_576, total - data.count)), !part.isEmpty else { break }
            data.append(part)
        }
        return data
    }
    /// Splits a chunk into its complete newline-terminated lines. When the chunk starts after byte
    /// zero its first line is the tail of a record cut by the chunk edge and is dropped; when it
    /// starts at zero the first record is kept.
    private func archiveChunkLines(_ chunk: Data, chunkStart: Int) -> ArchiveChunk? {
        let contentStart: Data.Index
        if chunkStart > 0 {
            guard let firstBreak = chunk.firstIndex(of: 10) else { return nil }
            contentStart = chunk.index(after: firstBreak)
        } else {
            contentStart = chunk.startIndex
        }
        guard contentStart < chunk.endIndex,
              let lastBreak = chunk[contentStart...].lastIndex(of: 10) else { return nil }
        let complete = chunk[contentStart...lastBreak]
        var offsets: [Int] = []
        var lineStart = complete.startIndex
        for index in complete.indices where complete[index] == 10 {
            offsets.append(chunkStart + chunk.distance(from: chunk.startIndex, to: lineStart))
            lineStart = complete.index(after: index)
        }
        let lines = String(decoding: complete, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        guard lines.count == offsets.count, let first = offsets.first else { return nil }
        return ArchiveChunk(lines: lines, lineOffsets: offsets, firstLineOffset: first)
    }
    /// Parses the chunk with the same readers ordinary history uses, then rewrites every sequence
    /// number from the chunk's line index to that line's file byte offset.
    private func archivePage(chunk: Data, chunkStart: Int, count: Int, generation: String, agent: String,
                             newest: Bool, reportsBackgroundTasks: Bool) throws -> ConversationArchivePage {
        guard let chunk = archiveChunkLines(chunk, chunkStart: chunkStart) else {
            // No complete record in this chunk. Continue from its first complete-line boundary, or
            // from the chunk start when the whole chunk was one cut record.
            let offset = chunkStart > 0 ? chunkStart : 0
            let complete = offset == 0
            let snapshot = ConversationSnapshot(messages: [], hasMore: !complete, generation: generation, clipped: false)
            return ConversationArchivePage(snapshot: snapshot,
                                           nextCursor: complete ? nil : encodeArchiveCursor(generation: generation, offset: offset),
                                           complete: complete)
        }
        let raw = chunk.lines
        let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw) : ClaudeCompactionSummary.Result(lines: raw, markers: [])
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
        let agentModel = TranscriptModelReader().read(lines: raw, agent: agent)
        let result = agent == "claude"
            ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: 0)
            : CodexTranscriptParser().parse(lines: lines, startingSeq: 0)
        // A record may repeat an id as it develops; one index by id beats a scan per update.
        var positions: [String: Int] = [:]
        var localMessages = result.messages
        for (index, message) in localMessages.enumerated() where positions[message.id] == nil { positions[message.id] = index }
        for update in result.updatedMessages {
            if let index = positions[update.id] { localMessages[index] = update }
        }
        let imageIndex = try TranscriptImageIndex().read(lines: lines, messages: localMessages, agent: agent)
        localMessages.append(contentsOf: imageIndex.supplementalMessages + compaction.markers)
        localMessages.sort { $0.seq < $1.seq }
        var responseState = TranscriptResponseReader.State()
        TranscriptResponseReader().consume(lines: lines, startingSeq: 0, messages: localMessages, agent: agent, into: &responseState)
        let presentation = remapped(TranscriptResponseReader().snapshot(responseState), offsets: chunk.lineOffsets)
        let messages = localMessages.map { remapped($0, offsets: chunk.lineOffsets) }.sorted { $0.seq < $1.seq }
        var tracker = BackgroundTaskTracker.State()
        BackgroundTaskTracker().consume(raw, into: &tracker)
        let tasks = reportsBackgroundTasks
            ? tracker.launched.values.filter { $0.isRunning(at: now()) }.map(\.task).sorted { $0.id < $1.id }
            : []
        return archivePage(messages: messages, images: imageIndex.records, presentation: presentation,
                           chunkStart: chunkStart, firstLineOffset: chunk.firstLineOffset, count: count,
                           generation: generation, backgroundTasks: tasks, agentModel: agentModel, newest: newest)
    }
    /// Rewrites a line index or a line's sequence number to its file byte offset.
    private func offset(_ seq: Int, in offsets: [Int]) -> Int {
        guard seq >= 0, seq < offsets.count else { return seq }
        return offsets[seq]
    }
    private func remapped(_ message: ChatMessage, offsets: [Int]) -> ChatMessage {
        guard message.seq >= 0, message.seq < offsets.count else { return message }
        return ChatMessage(id: message.id, seq: offsets[message.seq], role: message.role,
                           timestamp: message.timestamp, kind: message.kind)
    }
    private func remapped(_ result: TranscriptResponseReader.Result, offsets: [Int]) -> TranscriptResponseReader.Result {
        var result = result
        result.responses = result.responses.map { response in
            ConversationResponse(firstMessageID: response.firstMessageID, lastMessageID: response.lastMessageID,
                                 startedAt: response.startedAt, completedAt: response.completedAt,
                                 durationSeconds: response.durationSeconds, recordedDuration: response.recordedDuration,
                                 completed: response.completed,
                                 firstSeq: offset(response.firstSeq, in: offsets),
                                 lastSeq: offset(response.lastSeq, in: offsets))
        }
        return result
    }
    private func archivePage(messages: [ChatMessage], images: [TranscriptImageRecord],
                             presentation: TranscriptResponseReader.Result, chunkStart: Int, firstLineOffset: Int,
                             count: Int, generation: String, backgroundTasks: [BackgroundAgentTask],
                             agentModel: AgentModelState?, newest: Bool) -> ConversationArchivePage {
        guard !messages.isEmpty else {
            // Nothing to show, but records before this chunk may still exist.
            let complete = chunkStart == 0
            let snapshot = ConversationSnapshot(messages: [], hasMore: !complete, generation: generation, clipped: false)
            return ConversationArchivePage(snapshot: snapshot,
                                           nextCursor: complete ? nil : encodeArchiveCursor(generation: generation, offset: firstLineOffset),
                                           complete: complete)
        }
        var start = max(0, messages.count - count)
        while start > 0, messages[start - 1].seq == messages[start].seq { start -= 1 }
        // Walk from the newest record backwards until the byte budget would be crossed. The newest
        // record is always included, even when it alone exceeds the budget.
        let encoder = JSONEncoder()
        var chosen = messages.count
        var bytes = 0
        var index = messages.count - 1
        while index >= start {
            let size = (try? encoder.encode(messages[index]))?.count ?? 0
            if chosen != messages.count, bytes + size > Self.archivePageByteLimit { break }
            bytes += size
            chosen = index
            index -= 1
        }
        // A whole line's messages share one seq; splitting them would make the cursor skip a record.
        while chosen > 0, messages[chosen - 1].seq == messages[chosen].seq { chosen -= 1 }
        let pageMessages = Array(messages[chosen...])
        let ids = Set(pageMessages.map(\.id))
        // The cursor names the first returned line, so a page that reaches byte zero is the last one.
        let firstOffset = pageMessages.first?.seq ?? firstLineOffset
        let complete = firstOffset == 0
        let next = complete ? nil : encodeArchiveCursor(generation: generation, offset: firstOffset)
        let snapshot = ConversationSnapshot(
            messages: pageMessages,
            hasMore: !complete,
            generation: generation,
            clipped: false,
            responses: presentation.responses.filter { ids.contains($0.firstMessageID) || ids.contains($0.lastMessageID) },
            recordedRunSeconds: presentation.recordedRunSeconds,
            recordedTurnCount: presentation.recordedTurnCount,
            currentTurnStartedAt: presentation.currentTurnStartedAt,
            currentTurnCompleted: presentation.currentTurnCompleted,
            images: images.filter { ids.contains($0.messageID) }.map { $0.reference(generation: generation) },
            backgroundTasks: newest ? backgroundTasks : nil,
            agentModel: newest ? agentModel : nil)
        return ConversationArchivePage(snapshot: snapshot, nextCursor: next, complete: complete)
    }
    private func encodeArchiveCursor(generation: String, offset: Int) -> String {
        let data = (try? JSONEncoder().encode(ArchiveCursor(g: generation, s: offset))) ?? Data()
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func decodeArchiveCursor(_ cursor: String) throws -> ArchiveCursor {
        let invalid = BridgeError("invalid_input", "The archive cursor is invalid.", status: 400)
        guard cursor.utf8.count <= 4096 else { throw invalid }
        var text = cursor.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text),
              let payload = try? JSONDecoder().decode(ArchiveCursor.self, from: data),
              !payload.g.isEmpty, payload.g.utf8.count <= 128, payload.s >= 0 else { throw invalid }
        return payload
    }
    /// The only archive failure left: a configured chunk that is larger than the supported bound.
    private func archiveTooLarge() -> BridgeError {
        BridgeError("history_too_large", "The archive chunk exceeds the supported size.", status: 413)
    }

    private func page(_ messages: [ChatMessage], images: [TranscriptImageRecord], presentation: TranscriptResponseReader.Result, beforeSeq: Int?, limit: Int, generation: UUID, clipped: Bool, backgroundTasks: [BackgroundAgentTask], agentModel: AgentModelState? = nil) -> ConversationSnapshot {
        let eligible = messages.filter { beforeSeq == nil || $0.seq < beforeSeq! }
        let count = min(max(limit, 1), 200)
        var start = max(0, eligible.count - count)
        while start > 0, eligible[start - 1].seq == eligible[start].seq { start -= 1 }
        let pageMessages = Array(eligible[start...])
        let ids = Set(pageMessages.map(\.id))
        return ConversationSnapshot(messages: pageMessages, hasMore: start > 0, generation: generation.uuidString, clipped: clipped,
            responses: presentation.responses.filter { ids.contains($0.firstMessageID) || ids.contains($0.lastMessageID) },
            recordedRunSeconds: presentation.recordedRunSeconds, recordedTurnCount: presentation.recordedTurnCount,
            currentTurnStartedAt: presentation.currentTurnStartedAt, currentTurnCompleted: presentation.currentTurnCompleted,
            images: images.filter { ids.contains($0.messageID) }.map { $0.reference(generation: generation.uuidString) },
            // Only the newest page reports them; an earlier page must not re-add a task the reader scrolled past.
            backgroundTasks: beforeSeq == nil ? backgroundTasks : nil,
            agentModel: beforeSeq == nil ? agentModel : nil)
    }
}
