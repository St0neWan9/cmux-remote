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
    /// One whole-file read: every record from the beginning, with absolute sequence numbers.
    /// Only two are held at once, so an old conversation opened from the archive cannot evict the
    /// window records used by ordinary history.
    private struct ArchiveObservation {
        let inode: String
        let size: Int
        let modified: Date?
        let generation: String
        let messages: [ChatMessage]
        let images: [TranscriptImageRecord]
        let presentation: TranscriptResponseReader.Result
        let agentModel: AgentModelState?
        let trackerState: BackgroundTaskTracker.State
    }
    private var archiveObservations: [String: ArchiveObservation] = [:]
    private var archiveOrder: [String: Int] = [:]
    private var archiveSequence = 0
    private var observations: [String: Observation] = [:]
    /// Last-read order per path; an eviction takes the lowest, which is the least recently read.
    private var observationOrder: [String: Int] = [:]
    private var observationSequence = 0
    /// Long conversations are read from a bounded tail; the window start moves in whole steps so sequence numbers stay stable while the file grows.
    private let windowLimit: Int
    private let windowStep: Int
    /// The archive read's byte and message bounds. Exceeding either refuses the archive; ordinary
    /// history keeps its own smaller window and is unaffected.
    private let completeLimit: Int
    private let completeMessageLimit: Int
    /// A stable generation per transcript path, so an archive cursor survives a Bridge restart.
    private let generationStore: TranscriptGenerationStore
    private static let archivePageCountLimit = 200
    private static let archivePageByteLimit = 1_048_576
    private static let archiveReadChunk = 1_048_576
    private static let archiveObservationCapacity = 2
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
                completeLimit: Int = 67_108_864, completeMessageLimit: Int = 40_000) {
        self.windowLimit = max(1, windowLimit); self.windowStep = max(1, min(windowStep, windowLimit)); self.now = now
        self.generationStore = generationStore; self.completeLimit = max(1, completeLimit); self.completeMessageLimit = max(1, completeMessageLimit)
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
        // An archive page names its own stable generation. Its tool records may be far older than
        // anything the bounded history window still holds, so they resolve from a complete read.
        if generation != "current", let archived = try await archiveObservation(path: path, agent: agent, matching: generation) {
            return try await toolText(archived: archived, path: path, agent: agent, messageID: messageID, generation: generation,
                                      field: field, offset: offset, contentID: contentID, limit: limit)
        }
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

    private func toolText(archived observation: ArchiveObservation, path: String, agent: String, messageID: String, generation: String,
                          field: String, offset: Int, contentID: String?, limit: Int) async throws -> ToolTextPage {
        guard observation.messages.contains(where: { $0.id == messageID }) else {
            throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404)
        }
        let message = try await completeMessage(path: path, agent: agent, messageID: messageID)
        let text: String
        switch (message.kind, field) {
        case (.toolUse(let tool), "input"): text = tool.inputDetail ?? ""
        case (.toolUse(let tool), "output"): text = tool.output ?? ""
        case (.terminal(let tool), "input"): text = tool.command
        case (.terminal(let tool), "output"): text = tool.output ?? ""
        case (.fileEdit(let tool), "diff"): text = tool.unifiedDiff ?? ""
        default: throw BridgeError("invalid_input", "Select a supported field of a tool record.", status: 422)
        }
        guard await generationIsCurrent(path: path, generation: observation.generation) else {
            throw BridgeError("stale_detail", "The conversation record changed during this read.", status: 409)
        }
        let digest = IdentityCryptography().digest(Data(text.utf8))
        guard contentID == nil || contentID == digest else {
            throw BridgeError("stale_detail", "The tool output changed. Reload this detail.", status: 409)
        }
        try Task.checkCancellation()
        let total = text.unicodeScalars.count
        guard offset >= 0, offset <= total else { throw BridgeError("invalid_input", "The text page offset is invalid.", status: 422) }
        let pageText = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(offset).prefix(min(16_384, max(1, limit)))))
        let next = offset + pageText.unicodeScalars.count
        return ToolTextPage(messageID: messageID, generation: observation.generation, field: field, contentID: digest,
                            text: pageText, offset: offset, nextOffset: next < total ? next : nil, totalCharacters: total)
    }

    func image(path: String, agent: String, referenceID: String, generation: String) async throws -> TranscriptImageRecord {
        // An archive reference names the complete read's generation; the bounded window may no
        // longer contain the message, so resolve it from the observation that produced the page.
        if let archived = try await archiveObservation(path: path, agent: agent, matching: generation) {
            guard let record = archived.images.first(where: { $0.reference(generation: generation).id == referenceID }) else {
                throw BridgeError("image_unavailable", "This recorded image is unavailable.", status: 404)
            }
            guard await generationIsCurrent(path: path, generation: generation) else {
                throw BridgeError("stale_detail", "The image record changed. Reload the conversation.", status: 409)
            }
            return record
        }
        let current = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        guard current.generation == generation else { throw BridgeError("stale_detail", "The image record changed. Reload the conversation.", status: 409) }
        guard let record = observations[path]?.images.first(where: { $0.reference(generation: generation).id == referenceID }) else { throw BridgeError("image_unavailable", "This recorded image is unavailable.", status: 404) }
        return record
    }

    // MARK: - Complete archive

    private struct ArchiveMetadata {
        let inode: String
        let creationDate: Date?
        let size: Int
        let modified: Date?
    }
    private struct ArchiveCursor: Codable {
        let g: String
        let s: Int
    }
    private func archiveMetadata(_ path: String) throws -> ArchiveMetadata {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = (attributes[.size] as? NSNumber)?.intValue else {
                throw BridgeError("history_unavailable", "The conversation record size is unavailable.", status: 404)
            }
            return ArchiveMetadata(inode: "\(attributes[.systemFileNumber] ?? "unknown")",
                                   creationDate: attributes[.creationDate] as? Date,
                                   size: size, modified: attributes[.modificationDate] as? Date)
        } catch let error as BridgeError { throw error }
        catch { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
    }
    /// The newest `tail` messages, or the next older page named by an opaque cursor.
    ///
    /// The page carries at most 200 messages and about 1 MiB of encoded messages. Equal-sequence
    /// groups are never split, so `before_seq` can always continue without dropping a message.
    public func archive(path: String, agent: String, tail: Int?, cursor: String?, limit: Int,
                        reportsBackgroundTasks: Bool = true) async throws -> ConversationArchivePage {
        try Task.checkCancellation()
        let metadata = try archiveMetadata(path)
        let generation = await generationStore.generation(for: path, inode: metadata.inode,
                                                          creationDate: metadata.creationDate, size: metadata.size)
        let beforeSeq: Int?
        let count: Int
        if let cursor {
            // Refuse a cursor from another generation before paying for a complete read.
            let payload = try decodeArchiveCursor(cursor)
            guard payload.g == generation else {
                throw BridgeError("history_cursor_stale", "This archive cursor belongs to a different conversation record. Reload the archive.", status: 409)
            }
            beforeSeq = payload.s
            count = min(max(limit, 1), Self.archivePageCountLimit)
        } else {
            beforeSeq = nil
            count = min(max(tail ?? 100, 1), Self.archivePageCountLimit)
        }
        let observation = try await completeObservation(path: path, agent: agent, metadata: metadata, generation: generation)
        return archivePage(observation, beforeSeq: beforeSeq, count: count, generation: generation,
                           reportsBackgroundTasks: reportsBackgroundTasks)
    }
    /// The complete observation for an archive generation, rebuilt when it is not cached.
    /// Returns nil when the requested generation is not this path's stable generation.
    private func archiveObservation(path: String, agent: String, matching generation: String) async throws -> ArchiveObservation? {
        // Do not create a generation for an ordinary history request that merely names one.
        guard await generationStore.cachedGeneration(for: path) == generation,
              let metadata = try? archiveMetadata(path) else { return nil }
        // Re-evaluate the identity so a replacement or truncation since the page was read is caught.
        guard await generationStore.generation(for: path, inode: metadata.inode, creationDate: metadata.creationDate,
                                               size: metadata.size) == generation else { return nil }
        let observation = try await completeObservation(path: path, agent: agent, metadata: metadata, generation: generation)
        return observation.generation == generation ? observation : nil
    }
    private func generationIsCurrent(path: String, generation: String) async -> Bool {
        guard let metadata = try? archiveMetadata(path) else { return false }
        return await generationStore.generation(for: path, inode: metadata.inode, creationDate: metadata.creationDate,
                                                size: metadata.size) == generation
    }
    private func completeObservation(path: String, agent: String, metadata: ArchiveMetadata, generation: String) async throws -> ArchiveObservation {
        if let cached = archiveObservations[path], cached.inode == metadata.inode, cached.size == metadata.size,
           cached.modified == metadata.modified, cached.generation == generation {
            touchArchive(path)
            return cached
        }
        let observation = try await readCompleteObservation(path: path, agent: agent, metadata: metadata, generation: generation)
        storeArchive(observation, for: path)
        return observation
    }
    private func touchArchive(_ path: String) {
        archiveSequence += 1; archiveOrder[path] = archiveSequence
    }
    private func storeArchive(_ observation: ArchiveObservation, for path: String) {
        if archiveObservations[path] == nil, archiveObservations.count >= Self.archiveObservationCapacity,
           let oldest = archiveOrder.min(by: { $0.value < $1.value })?.key {
            archiveObservations[oldest] = nil; archiveOrder[oldest] = nil
        }
        archiveObservations[path] = observation
        touchArchive(path)
    }
    /// Walks the record from its first byte, feeding the same incremental parsers ordinary history
    /// uses. Sequence numbers are absolute line indexes, so they do not move with the history window.
    private func readCompleteObservation(path: String, agent: String, metadata: ArchiveMetadata, generation: String) async throws -> ArchiveObservation {
        guard metadata.size <= completeLimit else { throw archiveTooLarge() }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)) }
        catch { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        defer { try? handle.close() }
        var remainder = Data()
        var bytesRead = 0
        var lineIndex = 0
        var parserState = ChatTranscriptParseState()
        var tracker = BackgroundTaskTracker.State()
        var responseState = TranscriptResponseReader.State()
        var messages: [ChatMessage] = []
        var positions: [String: Int] = [:]
        var images: [TranscriptImageRecord] = []
        var imageIDs = Set<String>()
        var agentModel: AgentModelState?
        var carryLines: [String] = []
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: Self.archiveReadChunk), !chunk.isEmpty else { break }
            bytesRead += chunk.count
            guard bytesRead <= completeLimit else { throw archiveTooLarge() }
            remainder.append(chunk)
            guard let newline = remainder.lastIndex(of: 10) else { continue }
            let complete = Data(remainder[...newline])
            remainder = Data(remainder[remainder.index(after: newline)...])
            let decoded = String(decoding: complete, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
            let raw = decoded
            agentModel = TranscriptModelReader().read(lines: raw, agent: agent) ?? agentModel
            let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw, startingSeq: lineIndex) : .init(lines: raw, markers: [])
            let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
            let result = agent == "claude"
                ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: lineIndex, state: parserState)
                : CodexTranscriptParser().parse(lines: lines, startingSeq: lineIndex, state: parserState)
            parserState = result.state
            for update in result.updatedMessages {
                if let index = positions[update.id] { messages[index] = update }
            }
            let newStart = messages.count
            for message in result.messages where positions[message.id] == nil { messages.append(message) }
            // A tool call and its result can sit on either side of a chunk edge, so the image index
            // sees the same bounded tail of raw records that an appended history read uses.
            let context = Array(carryLines.suffix(64))
            let combined = context + lines
            let contextStart = lineIndex - context.count
            let contextMessages = messages.filter { $0.seq >= contextStart }
            let imageIndex = try TranscriptImageIndex().read(lines: combined, messages: contextMessages, agent: agent, startingSeq: contextStart)
            for record in imageIndex.records {
                let id = record.reference(generation: "deduplicate").id
                if imageIDs.insert(id).inserted { images.append(record) }
            }
            for message in imageIndex.supplementalMessages + compaction.markers where positions[message.id] == nil {
                messages.append(message)
            }
            // Only the records added by this chunk can be out of order; earlier messages keep their
            // positions, so sorting the suffix does not invalidate the identity index.
            messages.replaceSubrange(newStart..., with: messages[newStart...].sorted { $0.seq < $1.seq })
            for index in newStart..<messages.count { positions[messages[index].id] = index }
            TranscriptResponseReader().consume(lines: lines, startingSeq: lineIndex, messages: messages.filter { $0.seq >= lineIndex },
                                               agent: agent, into: &responseState)
            BackgroundTaskTracker().consume(raw, into: &tracker)
            lineIndex += decoded.count
            carryLines = Array(raw.suffix(64))
            if images.count > 512 { images = Array(images.prefix(512)) }
            guard messages.count <= completeMessageLimit else { throw archiveTooLarge() }
        }
        // A trailing line without its newline is not committed, exactly as in ordinary history.
        return ArchiveObservation(inode: metadata.inode, size: metadata.size, modified: metadata.modified,
                                  generation: generation, messages: messages, images: images,
                                  presentation: TranscriptResponseReader().snapshot(responseState),
                                  agentModel: agentModel, trackerState: tracker)
    }
    private func archiveTooLarge() -> BridgeError {
        BridgeError("history_too_large", "The conversation record exceeds the complete archive limit.", status: 413)
    }
    private func archivePage(_ observation: ArchiveObservation, beforeSeq: Int?, count: Int, generation: String,
                             reportsBackgroundTasks: Bool) -> ConversationArchivePage {
        let eligible = observation.messages.filter { beforeSeq == nil || $0.seq < beforeSeq! }
        guard !eligible.isEmpty else {
            let snapshot = ConversationSnapshot(messages: [], hasMore: false, generation: generation, clipped: false)
            return ConversationArchivePage(snapshot: snapshot, nextCursor: nil, complete: true)
        }
        var start = max(0, eligible.count - count)
        while start > 0, eligible[start - 1].seq == eligible[start].seq { start -= 1 }
        // Walk from the newest record backwards until the byte budget would be crossed. The newest
        // record is always included, even when it alone exceeds the budget.
        let encoder = JSONEncoder()
        var chosen = eligible.count
        var bytes = 0
        var index = eligible.count - 1
        while index >= start {
            let size = (try? encoder.encode(eligible[index]))?.count ?? 0
            if chosen != eligible.count, bytes + size > Self.archivePageByteLimit { break }
            bytes += size
            chosen = index
            index -= 1
        }
        // A whole line's messages share one seq; splitting them would make before_seq skip records.
        while chosen > 0, eligible[chosen - 1].seq == eligible[chosen].seq { chosen -= 1 }
        let pageMessages = Array(eligible[chosen...])
        let ids = Set(pageMessages.map(\.id))
        let complete = chosen == 0
        let next = complete ? nil : encodeArchiveCursor(generation: generation, beforeSeq: eligible[chosen].seq)
        let newest = beforeSeq == nil
        let tasks = reportsBackgroundTasks
            ? observation.trackerState.launched.values.filter { $0.isRunning(at: now()) }.map(\.task).sorted { $0.id < $1.id }
            : []
        let snapshot = ConversationSnapshot(
            messages: pageMessages,
            hasMore: !complete,
            generation: generation,
            clipped: false,
            responses: observation.presentation.responses.filter { ids.contains($0.firstMessageID) || ids.contains($0.lastMessageID) },
            recordedRunSeconds: observation.presentation.recordedRunSeconds,
            recordedTurnCount: observation.presentation.recordedTurnCount,
            currentTurnStartedAt: observation.presentation.currentTurnStartedAt,
            currentTurnCompleted: observation.presentation.currentTurnCompleted,
            images: observation.images.filter { ids.contains($0.messageID) }.map { $0.reference(generation: generation) },
            backgroundTasks: newest ? tasks : nil,
            agentModel: newest ? observation.agentModel : nil)
        return ConversationArchivePage(snapshot: snapshot, nextCursor: next, complete: complete)
    }
    private func encodeArchiveCursor(generation: String, beforeSeq: Int) -> String {
        let data = (try? JSONEncoder().encode(ArchiveCursor(g: generation, s: beforeSeq))) ?? Data()
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
    /// Re-parses the complete record with the larger explicit detail budget and keeps only the
    /// requested message, so an archive-surfaced tool record opens even when its line is far
    /// outside the history window.
    private func completeMessage(path: String, agent: String, messageID: String) async throws -> ChatMessage {
        let metadata = try archiveMetadata(path)
        guard metadata.size <= completeLimit else { throw archiveTooLarge() }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)) }
        catch { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        defer { try? handle.close() }
        var remainder = Data()
        var bytesRead = 0
        var lineIndex = 0
        var parserState = ChatTranscriptParseState()
        var found: ChatMessage?
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: Self.archiveReadChunk), !chunk.isEmpty else { break }
            bytesRead += chunk.count
            guard bytesRead <= completeLimit else { throw archiveTooLarge() }
            remainder.append(chunk)
            guard let newline = remainder.lastIndex(of: 10) else { continue }
            let complete = Data(remainder[...newline])
            remainder = Data(remainder[remainder.index(after: newline)...])
            let raw = String(decoding: complete, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
            let lines = agent == "claude"
                ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(ClaudeCompactionSummary().replace(raw, startingSeq: lineIndex).lines))
                : raw
            let result = agent == "claude"
                ? ClaudeTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: lineIndex, state: parserState)
                : CodexTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: lineIndex, state: parserState)
            parserState = result.state
            for message in result.messages + result.updatedMessages where message.id == messageID { found = message }
            lineIndex += raw.count
        }
        guard let found else { throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404) }
        return found
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
