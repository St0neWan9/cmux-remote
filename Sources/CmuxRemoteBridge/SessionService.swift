import Foundation
import CmuxRemoteCore
import CmuxAgentChat

/// Discovers existing conversations and only writes to explicit live bindings.
public actor SessionService {
    private struct Record: Sendable {
        var descriptor: SessionDescriptor
        let transcript: String?
    }
    private let cmux: any CmuxControlling
    private let transcriptRoots: [URL]
    private let files: ProjectFilePolicy
    private let commandLine = AgentCommandLine()
    private let reader = TranscriptReader()
    private var records: [String: Record] = [:]
    private var transcriptTails: [String: (size: Int, cwd: String?, lastMessage: Date?, title: String?)] = [:]
    /// Least recently used, so a burst of newly seen transcripts leaves the conversations still open in place.
    private var tailOrder: [String: Int] = [:]
    private var tailSequence = 0
    private let mutations: MutationLedger
    private var journal: MutationJournal?
    private var liveBindings: [String: JSONValue] = [:]
    private var eventBoot: String?
    private var eventSequence: Int?
    private let aliases: SessionAliasStore?
    private let modelCatalog: ModelChoiceCatalog
    /// The session read in progress, shared by callers that arrive while it runs.
    private var sessionsRead: Task<[SessionDescriptor], any Error>?
    private let taskLocator: BackgroundTaskLocator
    private let modelSwitch = CodexModelSwitch()
    private let claudeConfirmation = ClaudeModelConfirmation()

    public init(cmux: any CmuxControlling, home: URL, transcriptRoots: [URL], mutations: MutationLedger? = nil, journal: MutationJournal? = nil, aliases: SessionAliasStore? = nil,
                taskLocator: BackgroundTaskLocator = BackgroundTaskLocator()) {
        self.cmux = cmux; self.transcriptRoots = transcriptRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.files = ProjectFilePolicy(home: home); self.modelCatalog = ModelChoiceCatalog(home: home); self.mutations = mutations ?? MutationLedger(); self.journal = journal; self.aliases = aliases
        self.taskLocator = taskLocator
    }


    /// What one background task produced: the asynchronous Agent's own conversation, or a detached command's output.
    /// The task's record lives outside the conversation, so the read is bounded and paged like any other text.
    public func backgroundTask(id: String, taskID: String, offset: Int, limit: Int, discovered: Bool = false, access: SessionAccess? = nil) async throws -> BackgroundTaskContent {
        guard BackgroundTaskLocator.isValid(taskID), offset >= 0 else { throw BridgeError("invalid_input", "Choose a task and a valid text offset.", status: 422) }
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        guard let path = record.transcript else { throw BridgeError("task_unavailable", "No readable conversation record is available.", status: 404) }
        let listed = try await reader.history(path: path, agent: record.descriptor.agent, beforeSeq: nil, limit: 1,
                                              allowsUncreatedTranscript: record.descriptor.writable, reportsBackgroundTasks: record.descriptor.writable)
        let running = listed.backgroundTasks?.first { $0.id == taskID }
        guard let location = taskLocator.locate(transcript: path, taskID: taskID) else {
            throw BridgeError("task_unavailable", "This task's own record is no longer on this Mac.", status: 404)
        }
        let tool = running?.tool ?? (location.kind == .agent ? "Agent" : "Bash")
        let content: BackgroundTaskContent
        switch location.kind {
        case .agent:
            // A subagent writes the same records as a main conversation, so the phone reads it the same way.
            let conversation = try await reader.history(path: location.path, agent: "claude", beforeSeq: nil, limit: 100, includesSidechain: true)
            content = BackgroundTaskContent(taskID: taskID, tool: tool, summary: running?.summary ?? "", kind: .agent,
                                            running: running != nil, snapshot: conversation)
        case .output:
            let page = try Self.outputPage(location.path, offset: offset, limit: limit)
            content = BackgroundTaskContent(taskID: taskID, tool: tool, summary: running?.summary ?? "", kind: .output,
                                            running: running != nil, text: page.text, offset: offset, nextOffset: page.next, totalBytes: page.total)
        }
        try await recheck(record, capability: .conversationRead, access: access)
        return content
    }
    /// A page of a task's output, ending on a character boundary so the next page can continue from `next`.
    static func outputPage(_ path: String, offset: Int, limit: Int) throws -> (text: String, next: Int?, total: Int) {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let total = (attributes[.size] as? NSNumber)?.intValue, offset <= total else {
            throw BridgeError("invalid_input", "The text offset is invalid.", status: 422)
        }
        let count = min(max(limit, 1), 262_144)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let read = try handle.read(upToCount: min(count, total - offset)) ?? Data()
        let data = trimmedToCharacterBoundary(read)
        let next = offset + data.count < total ? offset + data.count : nil
        return (String(decoding: data, as: UTF8.self), next, total)
    }
    /// Drops a trailing UTF-8 scalar that the page cut in half; the next page starts on a whole character.
    private static func trimmedToCharacterBoundary(_ data: Data) -> Data {
        var lead = data.count
        while lead > 0, data[lead - 1] & 0xC0 == 0x80 { lead -= 1 }
        guard lead > 0 else { return Data() }
        let byte = data[lead - 1]
        let width = byte < 0x80 ? 1 : byte < 0xC0 ? 0 : byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
        // The page ends after this scalar's lead byte and any continuation bytes it already holds.
        return data.count - (lead - 1) < width ? data.prefix(lead - 1) : data
    }

    /// The Agent session a conversation currently answers for: a desktop resume forks the Agent's
    /// session id, and cmux addresses the live one, while the phone keeps the conversation's id.
    private func liveSessionID(_ id: String) async -> String {
        await aliases?.liveSessionID(conversationID: id) ?? id
    }
    public func status() async throws -> JSONValue {
        _ = try await cmux.request("system.ping", params: [:])
        let caps = try await cmux.request("system.capabilities", params: [:])
        return .object(["protocol": .string("cmux-remote/1"), "cmux": caps, "history_source": .string("local_transcript"), "preview_fidelity": .string("screen_best_effort")])
    }
    public func workspaces() async throws -> JSONValue { try await cmux.request("workspace.list", params: [:]) }
    public func feed() async throws -> JSONValue {
        let result = try await cmux.request("feed.list", params: [:])
        let items = result["items"].array ?? []
        let descriptors = items.contains(where: { $0["workstream_id"].string != nil }) ? try await sessions() : []
        let binding = FeedWorkspaceBinding()
        return .object(["items": .array(items.compactMap { item in
            guard var fields = item.object else { return nil }
            if let workspace = binding.workspace(for: item, sessions: descriptors) { fields["workspace_id"] = .string(workspace) }
            else { fields.removeValue(forKey: "workspace_id") }
            return .object(fields)
        })])
    }

    /// Last message time and the agent's own directory; the tail is re-read only when the file grew.
    /// Write time stands in only when the tail holds no dated message.
    private func transcriptFacts(_ path: String) -> (cwd: String?, updatedAt: Date?, title: String?)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue else { return nil }
        let modified = attributes[.modificationDate] as? Date
        if let cached = transcriptTails[path], cached.size == size {
            tailSequence += 1; tailOrder[path] = tailSequence
            return (cached.cwd, cached.lastMessage ?? modified, cached.title)
        }
        let cwd = size > 0 ? TranscriptWorkingDirectory().read(path: path, size: size) : nil
        let lastMessage = size > 0 ? TranscriptActivity().lastMessage(path: path, size: size) : nil
        // A record rewritten as the conversation develops, so a longer transcript may carry a newer name.
        let title = transcriptTails[path]?.title ?? TranscriptTitle().readTitle(path: path)
        if transcriptTails[path] == nil, transcriptTails.count >= 512, let oldest = tailOrder.min(by: { $0.value < $1.value })?.key {
            transcriptTails[oldest] = nil; tailOrder[oldest] = nil
        }
        tailSequence += 1; tailOrder[path] = tailSequence
        transcriptTails[path] = (size, cwd, lastMessage, title); return (cwd, lastMessage ?? modified, title)
    }
    /// The name the person gave each tab, which a cmux rename changes immediately; the vault keeps the agent's own title.
    private func surfaceTitles() async -> [String: String] {
        guard let tree = try? await cmux.request("system.tree", params: ["all_windows": .bool(true)]) else { return [:] }
        let workspaces = (tree["windows"].array ?? []).flatMap { $0["workspaces"].array ?? [] } + (tree["workspaces"].array ?? [])
        var titles: [String: String] = [:]
        for workspace in workspaces {
            for pane in workspace["panes"].array ?? [] {
                for surface in pane["surfaces"].array ?? [] {
                    guard let id = surface["id"].string, let title = surface["title"].string, !title.isEmpty else { continue }
                    titles[id.lowercased()] = title
                }
            }
        }
        return titles
    }
    /// A shell title is the directory the terminal sits in, so it never names the conversation.
    private func looksLikeADirectory(_ title: String, cwd: String?) -> Bool {
        if title.hasPrefix("~") || title.hasPrefix("/") { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if title.hasPrefix(home + "/") { return true }
        guard let cwd else { return false }
        return title == cwd || cwd.hasSuffix("/" + title)
    }
    /// The conversations cmux knows, read afresh.
    ///
    /// Every phone request authorizes against a fresh read, and one page asks for its history, live preview,
    /// models and the list at once. Each read walks every session the daemon holds and takes seconds, and the
    /// daemon answers them one after another, so a page waited for several reads in a row. Callers that arrive
    /// while a read is under way now share it rather than queue another behind it; that read started at most one
    /// read's duration earlier, and each caller still re-checks the record's binding before acting on it.
    public func sessions() async throws -> [SessionDescriptor] {
        if let sessionsRead { return try await sessionsRead.value }
        let read = Task { try await self.readSessions() }
        sessionsRead = read
        defer { if sessionsRead == read { sessionsRead = nil } }
        return try await read.value
    }
    private func readSessions() async throws -> [SessionDescriptor] {
        let vault = try await cmux.request("vault.sessions", params: ["limit": .number(200)])
        let dump = try? await cmux.request("chat.sessions.dump", params: [:])
        let tabTitles = await surfaceTitles()
        let authoritativeIDs = Set((dump?["sessions"].array ?? []).compactMap { $0["session_id"].string })
        // Vault includes sessions started outside cmux. It enriches known bindings,
        // never establishes which conversations belong in this companion.
        let registeredIDs = Set((dump?["sessions"].array ?? []).filter { hasCmuxBinding($0) }.compactMap { $0["session_id"].string })
        let hookedIDs = Set(liveBindings.filter { hasCmuxBinding($0.value) }.keys)
        // A conversation whose Agent has exited is absent from the live registry, but the daemon still vouches for the
        // binding it kept, and the row is what lets the phone reopen it. Its provenance is that retained binding.
        let resumableIDs = Set((vault["sessions"].array ?? []).filter { hasCmuxBinding($0) && $0["resumable"].bool == true }.compactMap { $0["session_id"].string })
        let cmuxIDs = registeredIDs.union(hookedIDs).union(resumableIDs)
        var discovered: [String: Record] = [:]
        for item in vault["sessions"].array ?? [] {
            guard let id = item["session_id"].string, cmuxIDs.contains(id), let agent = item["agent"].string,
                  ["claude", "codex"].contains(agent) else { continue }
            let path = allowedTranscript(item["file"].string)
            let named = item["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let descriptor = SessionDescriptor(id: id, agent: agent, title: named.flatMap { $0.isEmpty ? nil : $0 } ?? id, cwd: item["cwd"].string, state: item["status"].string ?? "unknown")
            discovered[id] = Record(descriptor: descriptor, transcript: path)
        }
        for item in dump?["sessions"].array ?? [] {
            guard let id = item["session_id"].string, cmuxIDs.contains(id), let agent = item["agent"].string, ["claude", "codex"].contains(agent) else { continue }
            var record = discovered[id] ?? Record(descriptor: SessionDescriptor(id: id, agent: agent, title: id, cwd: item["cwd"].string), transcript: allowedTranscript(item["transcript_path"].string))
            record.descriptor.workspaceID = item["workspace_id"].string
            record.descriptor.surfaceID = item["surface_id"].string
            record.descriptor.state = item["state"].string ?? "unknown"
            // cmux verifies its own daemon sessions; for a desktop session it only keeps the row, so this
            // side applies the same rule it documents: an ended Agent whose transcript still records the
            // working directory can be reopened, and nothing else may claim it can.
            record.descriptor.resumable = item["resumable"].bool == true || desktopResumable(item, record: record)
            discovered[id] = record
        }
        for (id, record) in discovered {
            guard let path = record.transcript, let facts = transcriptFacts(path) else { continue }
            let old = record.descriptor
            // An unnamed session falls back to the summary the agent writes into its own transcript.
            let named = old.title == old.id ? facts.title ?? old.title : old.title
            discovered[id]?.descriptor = SessionDescriptor(id: old.id, agent: old.agent, title: named, cwd: facts.cwd ?? old.cwd, workspaceID: old.workspaceID,
                                                           surfaceID: old.surfaceID, state: old.state, updatedAt: facts.updatedAt, resumable: old.resumable)
        }
        await reconcileResumedSessions(&discovered)
        records = discovered
        for (id, record) in records {
            guard let old = record.descriptor.surfaceID.map({ tabTitles[$0.lowercased()] }), let title = old else { continue }
            // An unnamed tab shows the shell's directory, expanded or not; the agent's own title is more useful than a path.
            guard !looksLikeADirectory(title, cwd: record.descriptor.cwd) else { continue }
            let current = record.descriptor
            records[id]?.descriptor = SessionDescriptor(id: current.id, agent: current.agent, title: title, cwd: current.cwd, workspaceID: current.workspaceID,
                                                        surfaceID: current.surfaceID, state: current.state, updatedAt: current.updatedAt, resumable: current.resumable)
        }
        for (id, event) in liveBindings {
            guard records[id] != nil else { continue }
            // Hook bindings fill in where the daemon's row carries none, and a hook-reported end always wins.
            // A daemon row that still holds a live binding outranks an older retained hook binding: fresh
            // cmux process state, including a reused terminal, must not be overwritten by a stale hook.
            let bound = records[id]?.descriptor.workspaceID != nil && records[id]?.descriptor.surfaceID != nil
            guard !(authoritativeIDs.contains(id) && bound) || event["state"].string == "ended" else { continue }
            records[id]?.descriptor.workspaceID = event["workspace_id"].string
            records[id]?.descriptor.surfaceID = event["surface_id"].string
            records[id]?.descriptor.state = event["state"].string ?? "unknown"
        }
        return records.values.map(\.descriptor).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    /// Whether a desktop row the daemon keeps after an exit can still be reopened.
    ///
    /// cmux reports `resumable` for its own daemon sessions only; a desktop row carries the retained
    /// workspace/surface and a transcript path instead. The rule matches what `resume` needs: the Agent
    /// is gone (`ended`), the workspace is still known, and the transcript is both readable under a
    /// configured root and records the directory the Agent ran in.
    private func desktopResumable(_ item: JSONValue, record: Record) -> Bool {
        guard item["state"].string == "ended",
              record.descriptor.workspaceID != nil,
              let path = record.transcript,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0 else { return false }
        return TranscriptWorkingDirectory().read(path: path, size: size) != nil
    }
    public func acceptEvent(_ frame: JSONValue) {
        if let boot = frame["boot_id"].string, eventBoot != nil && eventBoot != boot { liveBindings.removeAll(); records.removeAll() }
        eventBoot = frame["boot_id"].string ?? eventBoot
        if frame["type"].string == "ack", frame["resume"]["gap"].bool == true { liveBindings.removeAll(); records.removeAll() }
        if let seq = frame["seq"].int { eventSequence = seq }
        guard frame["type"].string == "event", frame["category"].string == "agent",
              let id = frame["payload"]["session_id"].string,
              let workspace = frame["workspace_id"].string, let surface = frame["surface_id"].string else { return }
        let name = frame["payload"]["hook_event_name"].string ?? ""
        let state = name == "SessionEnd" ? "ended" : (name == "Stop" ? "idle" : "working")
        if liveBindings.count >= 512 { liveBindings.removeAll() }
        liveBindings[id] = .object(["workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string(state)])
        records[id]?.descriptor.workspaceID = state == "ended" ? nil : workspace
        records[id]?.descriptor.surfaceID = state == "ended" ? nil : surface
        records[id]?.descriptor.state = state
    }
    public func eventCursor() -> Int? { eventSequence }
    /// A disconnected/gapped stream cannot keep hook-derived targets writable.
    public func invalidateEventBindings() {
        liveBindings.removeAll(); records.removeAll(); eventSequence = nil; eventBoot = nil
    }

    /// A cheap identity of what one subscribed resource would answer, or nil when it cannot be proven.
    ///
    /// Answers from the records the last discovery and hook events left behind plus the transcript's own
    /// metadata: no daemon round trip, no file read. Only a transcript-backed history has such a signal.
    /// The session list is assembled from three daemon reads and a preview is the daemon's screen text,
    /// so both answer nil and are rebuilt on every tick, as before.
    func subscriptionStamp(_ resource: LinkSubscriptionResource) async -> (stamp: String, workspace: String)? {
        // A task's record is a file beside the conversation; its size and write time are the whole answer.
        if case .sessionTask(let id, let taskID) = resource, let record = records[id], let path = record.transcript,
           let workspace = record.descriptor.workspaceID,
           let location = taskLocator.locate(transcript: path, taskID: taskID),
           let attributes = try? FileManager.default.attributesOfItem(atPath: location.path),
           let size = (attributes[.size] as? NSNumber)?.intValue, let modified = (attributes[.modificationDate] as? Date) {
            return ("task:\(location.path):\(size):\(modified.timeIntervalSinceReferenceDate)", workspace)
        }
        guard case .sessionHistory(let id) = resource, let record = records[id], let path = record.transcript,
              let workspace = record.descriptor.workspaceID else { return nil }
        let descriptor = record.descriptor
        guard let transcript = await reader.stamp(path: path),
              // Suspension may let a discovery or hook event move the binding; that is a change too.
              records[id]?.descriptor == descriptor else { return nil }
        // The binding decides the history's background tasks and its scope, so it is part of the identity.
        return ("\(transcript):\(workspace):\(descriptor.surfaceID ?? ""):\(descriptor.writable)", workspace)
    }

    /// - Parameter discovered: The caller resolved this id against a fresh discovery for the same request.
    public func history(id: String, beforeSeq: Int?, limit: Int, discovered: Bool = false, access: SessionAccess? = nil) async throws -> ConversationSnapshot {
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        guard let path = record.transcript else { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        let reader = reader; let agent = record.descriptor.agent
        // A detached task dies with the agent process that started it, so a session no longer bound to a
        // running agent reports none: its record keeps launches that were never marked finished.
        let result = try await reader.history(path: path, agent: agent, beforeSeq: beforeSeq, limit: limit,
                                             allowsUncreatedTranscript: record.descriptor.writable,
                                             reportsBackgroundTasks: record.descriptor.writable)
        try await recheck(record, capability: .conversationRead, access: access)
        return result
    }

    /// Returns a bounded, revision-bound page from an authorized session's tool record.
    public func toolText(id: String, messageID: String, generation: String, field: String,
                         offset: Int, contentID: String?, limit: Int, discovered: Bool = false, access: SessionAccess? = nil) async throws -> ToolTextPage {
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        guard let path = record.transcript else { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        let result = try await reader.toolText(path: path, agent: record.descriptor.agent, messageID: messageID,
                                             generation: generation, field: field, offset: offset, contentID: contentID, limit: limit)
        try await recheck(record, capability: .conversationRead, access: access)
        return result
    }

    /// Reads only a transcript-bound image; project bytes additionally require project-read authority.
    public func image(id: String, referenceID: String, generation: String, discovered: Bool = false, access: SessionAccess? = nil) async throws -> Data {
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        guard let path = record.transcript else { throw BridgeError("image_unavailable", "No recorded image is available.", status: 404) }
        let image = try await reader.image(path: path, agent: record.descriptor.agent, referenceID: referenceID, generation: generation)
        let bytes: Data
        let required: [ClientCapability]
        switch image.source {
        case .recorded(let data): bytes = data; required = [.conversationRead]
        case .projectPath(let referenced):
            if record.descriptor.id.hasPrefix("tui:"), let data = try await cmux.request("conversation.image.read", params: ["session_id": .string(record.descriptor.id), "path": .string(referenced)])["data_b64"].string, let decoded = Data(base64Encoded: data) {
                bytes = decoded; required = [.conversationRead]
            } else {
                required = [.conversationRead, .projectRead]
                try await access?.require(.projectRead, workspace: record.descriptor.workspaceID)
                guard let root = record.descriptor.cwd else { throw BridgeError("file_forbidden", "No approved project is available.", status: 403) }
                let policy = files
                let reading = Task.detached { try ProjectImageReader(policy: policy).read(root: root, referencedPath: referenced) }
                bytes = try await withTaskCancellationHandler { try await reading.value } onCancel: { reading.cancel() }
                try await recheck(record, capability: .projectRead, access: access)
            }
        }
        let decoding = Task.detached { try HistoricalImageProjection().preview(bytes) }
        let result = try await withTaskCancellationHandler { try await decoding.value } onCancel: { decoding.cancel() }
        _ = try await reader.image(path: path, agent: record.descriptor.agent, referenceID: referenceID, generation: generation)
        try await recheck(record, capabilities: required, access: access)
        try Task.checkCancellation()
        return result
    }

    /// - Parameter discovered: The caller already authorized against a fresh discovery for this request.
    ///   Running it again here doubled the daemon round trips of every preview read to no effect.
    public func preview(id: String, discovered: Bool = false, access: SessionAccess? = nil) async throws -> PreviewSnapshot {
        if !discovered { _ = try await sessions() }
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        guard record.descriptor.writable, let surface = record.descriptor.surfaceID else { return PreviewSnapshot(text: nil, available: false) }
        let snapshot = try await cmux.request("surface.read_text", params: ["surface_id": .string(surface)])
        let lines = (snapshot["text"].string ?? "").components(separatedBy: .newlines)
        let text = AgentChatProseScreenExtractor().extract(lines: lines, agentKind: ChatAgentKind(source: record.descriptor.agent))
        // Compaction is printed on the agent's own working line, so it is read from the same rows.
        let compacting = TuiCompactionScreen.isCompacting(rows: lines)
        try await recheck(record, capability: .conversationRead, access: access)
        return PreviewSnapshot(text: text, available: true, compacting: compacting)
    }

    public func send(id: String, request: SendRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        guard (!request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !request.attachments.isEmpty), request.text.utf8.count <= 65_536 else { throw BridgeError("invalid_input", "Enter a prompt within the size limit.") }
        let attachments = try ChatImagePolicy().attachments(request.attachments)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let legacySignature = request.attachments.isEmpty ? "send:\(id):\(request.text)" : "send:\(id):\(String(decoding: try encoder.encode(request), as: UTF8.self))"
        let payload: JSONValue = request.attachments.isEmpty ? .string(request.text) : .object(["text": .string(request.text), "attachments": try JSONDecoder().decode(JSONValue.self, from: encoder.encode(request.attachments))])
        let signature = try MutationLedger.fingerprint(action: "send", resource: id, payload: payload)
        if let receipt = try await existing(request.operationID, signature: signature, legacySignature: legacySignature, access: access) { return receipt }
        // The daemon backend clears its own Agent input for a phone send; the desktop backend still requires an empty prompt.
        let session = try await verifiedBinding(id, requiresEmptyPrompt: !id.hasPrefix("tui:"), access: access)
        if let receipt = try await begin(request.operationID, signature: signature, workspace: session.workspaceID, capability: .conversationControl, legacySignature: legacySignature, access: access) { return receipt }
        try await validateMutationBinding(session, access: access)
        do {
            var params: [String: JSONValue] = ["session_id": .string(await liveSessionID(session.id)), "text": .string(request.text), "operation_id": .string(request.operationID.uuidString), "backend_operation_key": .string(IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + request.operationID.uuidString).utf8))), "workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)]
            if !attachments.isEmpty { params["attachments"] = .array(attachments) }
            let result = try await cmux.request("mobile.chat.send", params: params)
            guard result["submitted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm prompt submission; inspect its draft before retrying.", status: 409) }
            return try await complete(request.operationID, access: access)
        } catch { journal?.uncertain(id: request.operationID); throw mutationError(error) }
    }

    /// The models this conversation's agent offers on this Mac.
    public func models(id: String, discovered: Bool = false, access: SessionAccess? = nil) async throws -> ModelChoiceList {
        let record = try await authorizedRecord(id, capability: .conversationRead, discovered: discovered, access: access)
        let list = modelCatalog.choices(agent: record.descriptor.agent)
        try await recheck(record, capability: .conversationRead, access: access)
        return list
    }

    /// Switches a live agent to another model with the agent's own command.
    ///
    /// Claude Code takes `/model <name>` as an ordinary prompt and saves it as its default for new sessions.
    /// Codex has no model argument, so its picker is walked and the choice applied to this session only.
    /// Only an agent waiting at its prompt is switched: a turn in progress would take the command as input.
    public func switchModel(id: String, request: ModelSwitchRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        let name = try AgentModelName.validated(request.model)
        let signature = try MutationLedger.fingerprint(action: "model", resource: id, payload: .object(["model": .string(name), "confirm": .bool(request.confirm)]))
        if let receipt = try await existing(request.operationID, signature: signature, access: access) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: !id.hasPrefix("tui:"), access: access)
        guard ["claude", "codex"].contains(session.agent) else { throw BridgeError("unsupported", "This agent cannot switch models from the phone.", status: 422) }
        guard !session.state.hasPrefix("working") else { throw BridgeError("agent_busy", "Wait for the Agent to finish its turn before switching models.", status: 409) }
        // Codex lists models by label, so the offered label is matched as well as the id; the session keeps its effort.
        var candidates = [name], effort: String?
        if session.agent == "codex" {
            if let label = modelCatalog.choices(agent: "codex").choices.first(where: { $0.id.lowercased() == name.lowercased() })?.label { candidates.append(label) }
            if let path = records[id]?.transcript { effort = try? await reader.history(path: path, agent: "codex", beforeSeq: nil, limit: 1).agentModel?.effort }
        }
        if let receipt = try await begin(request.operationID, signature: signature, workspace: session.workspaceID, capability: .conversationControl, access: access) { return receipt }
        try await validateMutationBinding(session, access: access)
        do {
            let key = IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + request.operationID.uuidString).utf8))
            var params: [String: JSONValue] = ["session_id": .string(await liveSessionID(session.id)), "operation_id": .string(request.operationID.uuidString), "backend_operation_key": .string(key), "workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)]
            if session.agent == "claude" {
                params["text"] = .string("/model " + name)
                let result = try await cmux.request("mobile.chat.send", params: params)
                guard result["submitted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm the model command; inspect the Agent.", status: 409) }
                // A long conversation makes Claude Code ask before it switches; that question is answered as the reader chose.
                if id.hasPrefix("tui:") {
                    params["confirm"] = .bool(request.confirm)
                    _ = try await cmux.request("mobile.chat.model", params: params)
                } else {
                    try await claudeConfirmation.settle(on: desktopConsole(session, access: access), confirm: request.confirm)
                }
            } else if id.hasPrefix("tui:") {
                params["candidates"] = .array(candidates.map(JSONValue.string)); if let effort { params["effort"] = .string(effort) }
                let result = try await cmux.request("mobile.chat.model", params: params)
                guard result["switched"].bool == true else { throw BridgeError("outcome_unknown", "The daemon did not confirm the model switch; inspect the Agent.", status: 409) }
            } else {
                try await modelSwitch.run(on: desktopConsole(session, access: access), candidates: candidates, effort: effort)
            }
            return try await complete(request.operationID, access: access)
        } catch { journal?.uncertain(id: request.operationID); throw mutationError(error) }
    }

    /// The desktop terminal behind a verified binding; every write first rechecks that the same terminal is still there.
    private func desktopConsole(_ session: SessionDescriptor, access: SessionAccess?) -> AgentConsole {
        let cmux = cmux, target: [String: JSONValue] = ["workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)]
        return AgentConsole(rows: {
            (try await cmux.request("surface.read_text", params: target))["text"].string?.components(separatedBy: .newlines) ?? []
        }, write: { [self] text, _ in
            let state = try await cmux.request("surface.input_state", params: target)
            guard state["workspace_id"].string?.lowercased() == session.workspaceID?.lowercased(), state["surface_id"].string?.lowercased() == session.surfaceID?.lowercased(),
                  state["terminal"].bool != false else { throw BridgeError("stale_binding", "The agent's terminal binding changed. Refresh the task.", status: 409) }
            try await validateMutationBinding(session, access: access)
            var params = target; params["text"] = .string(text)
            let result = try await cmux.request("mobile.terminal.input", params: params)
            guard result["accepted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm terminal input; inspect the Agent.", status: 409) }
        })
    }

    /// Reopens one Agent session in a new terminal, continuing the same conversation.
    /// The caller names only the conversation; the Agent session id and the directory come from the Bridge's own
    /// binding and the Agent's transcript, so a device can never choose what command runs where.
    public func resume(id: String, request: ResumeRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        let operationID = request.operationID
        let signature = try MutationLedger.fingerprint(action: "resume", resource: id, payload: .string(id))
        if let receipt = try await existing(operationID, signature: signature, access: access) { return receipt }
        _ = try await sessions()
        let value = try await record(id).descriptor
        guard value.resumable, let workspace = value.workspaceID else { throw BridgeError("read_only", "This conversation has no Agent session left to reopen.", status: 409) }
        // Reopening starts a process in the workspace, so it needs the same grant as starting one.
        try await access?.require(.conversationStart, workspace: workspace)
        if let receipt = try await begin(operationID, signature: signature, workspace: workspace, capability: .conversationStart, access: access) { return receipt }
        do {
            if id.hasPrefix("tui:") {
                // The daemon owns the reopen: it runs the recorded launcher itself and deduplicates by key.
                let result = try await cmux.request("mobile.chat.resume", params: [
                    "session_id": .string(value.id),
                    "operation_key": .string(IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + operationID.uuidString).utf8)))])
                guard result["surface_id"].string != nil else { throw BridgeError("outcome_unknown", "cmux did not confirm the reopened terminal.", status: 409) }
            } else {
                try await desktopResume(value, workspace: workspace, access: access)
            }
            return try await complete(operationID, access: access)
        } catch { journal?.uncertain(id: operationID); throw mutationError(error) }
    }

    /// Desktop cmux has no resume RPC, so reopening is the same fixed terminal start a new session uses:
    /// the command, the Agent session and the directory all come from the Bridge's own record.
    private func desktopResume(_ value: SessionDescriptor, workspace: String, access: SessionAccess?) async throws {
        guard let path = records[value.id]?.transcript,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0,
              let recorded = TranscriptWorkingDirectory().read(path: path, size: size),
              let directory = try? files.projectRoot(recorded),
              let agent = LaunchAgent(rawValue: value.agent) else { throw BridgeError("read_only", "This conversation's directory is no longer available.", status: 409) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BridgeError("read_only", "This conversation's directory is no longer available.", status: 409)
        }
        try await access?.require(.conversationStart, workspace: workspace)
        // The shell that owns the terminal is the one the Agent ran under, so a resumed command sees the same PATH.
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        let command = agent.resumeCommand(sessionID: value.id)
        let line = "\(commandLine.quoted(shell)) -ic \(commandLine.quoted(command))"
        let result: JSONValue
        do {
            result = try await cmux.request("surface.create", params: [
                "workspace_id": .string(workspace), "type": .string("terminal"), "working_directory": .string(directory.path),
                "initial_input": .string(line + "\r"), "focus": .bool(false)])
        } catch let error as BridgeError where error.code == "outcome_unknown" {
            throw error
        } catch {
            throw BridgeError("outcome_unknown", "The reopened terminal may or may not exist; check the workspace before trying again.", status: 409)
        }
        guard let surface = result["surface_id"].string, UUID(uuidString: surface) != nil else {
            throw BridgeError("outcome_unknown", "cmux did not confirm the reopened terminal.", status: 409)
        }
        // The resumed Agent forks a new session id on that surface; the conversation follows it once
        // the inventory sees it there.
        await aliases?.setTarget(surface, conversationID: value.id)
    }
    /// Folds a desktop resume back into one conversation: the Agent session the resume produced on the
    /// recorded surface takes over the conversation's identity, transcript and live state, and its own
    /// row disappears from the list.
    private func reconcileResumedSessions(_ discovered: inout [String: Record]) async {
        guard let aliases else { return }
        for id in await aliases.trackedConversationIDs() {
            guard await aliases.liveSessionID(conversationID: id) == nil,
                  let surface = await aliases.target(conversationID: id),
                  let fresh = discovered.values.first(where: {
                      $0.descriptor.surfaceID?.lowercased() == surface.lowercased() && $0.descriptor.id != id
                          && $0.descriptor.state != "ended"
                  }) else { continue }
            await aliases.setAlias(conversationID: id, sessionID: fresh.descriptor.id)
        }
        for (old, new) in await aliases.aliasPairs() {
            guard let fresh = discovered[new] else { continue }
            let descriptor = SessionDescriptor(id: old, agent: fresh.descriptor.agent, title: fresh.descriptor.title, cwd: fresh.descriptor.cwd,
                                               workspaceID: fresh.descriptor.workspaceID, surfaceID: fresh.descriptor.surfaceID,
                                               state: fresh.descriptor.state, updatedAt: fresh.descriptor.updatedAt, resumable: false)
            discovered[old] = Record(descriptor: descriptor, transcript: fresh.transcript)
            discovered[new] = nil
        }
    }

    public func interrupt(id: String, request: InterruptRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        let legacySignature = "interrupt:\(id):\(request.hard)"
        let signature = try MutationLedger.fingerprint(action: "interrupt", resource: id, payload: .bool(request.hard))
        if let receipt = try await existing(request.operationID, signature: signature, legacySignature: legacySignature, access: access) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: false, access: access)
        if let receipt = try await begin(request.operationID, signature: signature, workspace: session.workspaceID, capability: .conversationControl, legacySignature: legacySignature, access: access) { return receipt }
        try await validateMutationBinding(session, access: access)
        do {
            let result = try await cmux.request("mobile.chat.interrupt", params: ["session_id": .string(await liveSessionID(session.id)), "hard": .bool(request.hard), "operation_id": .string(request.operationID.uuidString), "backend_operation_key": .string(IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + request.operationID.uuidString).utf8))), "workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)])
            guard result["interrupted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm interruption.", status: 409) }
            return try await complete(request.operationID, access: access)
        } catch { journal?.uncertain(id: request.operationID); throw mutationError(error) }
    }

    public func reply(requestID: String, body: JSONValue, access: SessionAccess? = nil) async throws -> MutationReceipt {
        guard let rawID = body["operation_id"].string, let operation = UUID(uuidString: rawID), let kind = body["kind"].string else { throw BridgeError("invalid_input", "A decision identity and kind are required.") }
        var payload = body.object ?? [:]; payload["operation_id"] = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let legacySignature = "reply:\(requestID):\(String(decoding: try encoder.encode(JSONValue.object(payload)), as: UTF8.self))"
        let signature = try MutationLedger.fingerprint(action: "reply", resource: requestID, payload: .object(payload))
        if let receipt = try await existing(operation, signature: signature, legacySignature: legacySignature, access: access) { return receipt }
        let items = try await feed()["items"].array ?? []
        guard let pending = items.first(where: { $0["request_id"].string == requestID && $0["status"].string == "pending" }), pending["kind"].string == kind else { throw BridgeError("request_expired", "This request is no longer waiting for a decision.", status: 409) }
        try await access?.require(.feedReply, workspace: pending["workspace_id"].string)
        // Authorization suspends the actor. Hook events/session refresh may move or end the target meanwhile.
        if pending["workstream_id"].string != nil {
            let live = records.values.map(\.descriptor).filter(\.writable)
            let current = FeedWorkspaceBinding().workspace(for: pending, sessions: live)
            guard current != nil, current == pending["workspace_id"].string?.lowercased() else {
                throw BridgeError("stale_binding", "The Feed target changed during authorization. Refresh before replying.", status: 409)
            }
        }
        let method: String; var params: [String: JSONValue] = ["request_id": .string(requestID)]
        switch kind {
        case "permissionRequest":
            guard let raw = body["mode"].string, let mode = FeedDecisionMode(rawValue: raw), FeedDecisionPolicy().modes(for: pending).contains(mode) else { throw BridgeError("invalid_input", "Choose an available permission decision.") }
            method = "feed.permission.reply"; params["mode"] = .string(mode.rawValue)
        case "exitPlan":
            guard let raw = body["mode"].string, let mode = FeedDecisionMode(rawValue: raw), mode.supports(kind: kind) else { throw BridgeError("invalid_input", "Choose an available plan decision.") }
            method = "feed.exit_plan.reply"; params["mode"] = .string(mode.rawValue)
            if let feedback = body["feedback"].string, !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { params["feedback"] = .string(feedback) }
        case "question":
            guard let choices = body["selections"].array, choices.allSatisfy({ $0.string != nil }) else { throw BridgeError("invalid_input", "Choose an answer.") }
            method = "feed.question.reply"; params["selections"] = .array(choices)
        default: throw BridgeError("unsupported", "cmux does not expose this decision.", status: 422)
        }
        if let receipt = try await begin(operation, signature: signature, workspace: pending["workspace_id"].string, capability: .feedReply, legacySignature: legacySignature, access: access) { return receipt }
        try await access?.require(.feedReply, workspace: pending["workspace_id"].string)
        if pending["workstream_id"].string != nil {
            let current = FeedWorkspaceBinding().workspace(for: pending, sessions: records.values.map(\.descriptor).filter(\.writable))
            guard current != nil, current == pending["workspace_id"].string?.lowercased() else { throw BridgeError("stale_binding", "The Feed binding changed before execution.", status: 409) }
        }
        do {
            let result = try await cmux.request(method, params: params)
            guard result["delivered"].bool != false, result["accepted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm the decision.", status: 409) }
            return try await complete(operation, access: access)
        }
        catch { journal?.uncertain(id: operation); throw mutationError(error) }
    }

    public func file(id: String, path: String, discovered: Bool = false, access: SessionAccess? = nil) async throws -> TextFileSnapshot {
        let record = try await authorizedRecord(id, capability: .projectRead, discovered: discovered, access: access)
        guard let cwd = record.descriptor.cwd else { throw BridgeError("project_unavailable", "This conversation has no project directory.", status: 404) }
        let file = try files.resolve(root: cwd, relativePath: path)
        let data = try Data(contentsOf: file)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw BridgeError("unsupported_file", "The initial preview supports UTF-8 text files.", status: 415) }
        try await recheck(record, capability: .projectRead, access: access)
        return TextFileSnapshot(path: path, text: text, truncated: false)
    }
    public func changes(id: String, discovered: Bool = false, access: SessionAccess? = nil) async throws -> JSONValue {
        let record = try await authorizedRecord(id, capability: .projectRead, discovered: discovered, access: access)
        let cwd = try projectRoot(record)
        let output = try await GitReader().run(directory: cwd, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=normal"])
        try await recheck(record, capability: .projectRead, access: access)
        return .object(["entries": .array(output.split(separator: "\0").map { .string(String($0)) })])
    }
    public func diff(id: String, path: String?, discovered: Bool = false, access: SessionAccess? = nil) async throws -> TextFileSnapshot {
        let record = try await authorizedRecord(id, capability: .projectRead, discovered: discovered, access: access)
        let cwd = try projectRoot(record)
        let listed = try await GitReader().run(directory: cwd, arguments: ["diff", "--no-ext-diff", "--no-textconv", "--name-only", "-z", "HEAD", "--"])
        let changed = listed.split(separator: "\0").map(String.init)
        let permitted = Set(changed.filter { (try? files.resolveDiffPath(root: cwd, relativePath: $0)) != nil })
        // Literal pathspecs also match directory prefixes. No chosen path may include a denied descendant.
        let safe = permitted.filter { candidate in !changed.contains(where: { $0.hasPrefix(candidate + "/") && !permitted.contains($0) }) }
        let allowed: [String]
        if let path {
            guard changed.contains(path), safe.contains(path) else { throw BridgeError("file_forbidden", "Select an exact shareable changed file.", status: 403) }
            allowed = [path]
        }
        else {
            allowed = Array(safe).sorted()
        }
        try await recheck(record, capability: .projectRead, access: access)
        guard !allowed.isEmpty else { return TextFileSnapshot(path: path ?? "", text: "", truncated: false) }
        let arguments = ["diff", "--no-ext-diff", "--no-textconv", "HEAD", "--"] + allowed
        let text = try await GitReader().run(directory: cwd, arguments: arguments)
        try await recheck(record, capability: .projectRead, access: access)
        return TextFileSnapshot(path: path ?? "", text: text, truncated: false)
    }

    private func projectRoot(_ record: Record) throws -> String {
        guard let cwd = record.descriptor.cwd, cwd != "/" else { throw BridgeError("project_unavailable", "This conversation has no project directory.", status: 404) }
        return try files.projectRoot(cwd).path
    }
    private func record(_ id: String) async throws -> Record {
        if records[id] == nil { _ = try await sessions() }
        guard let record = records[id] else { throw BridgeError("session_not_found", "This conversation is no longer available.", status: 404) }
        return record
    }
    private func verifiedBinding(_ id: String, requiresEmptyPrompt: Bool, access: SessionAccess?) async throws -> SessionDescriptor {
        _ = try await sessions()
        let value = try await record(id).descriptor
        guard value.writable, let surface = value.surfaceID, let workspace = value.workspaceID else { throw BridgeError("read_only", "This historical conversation has no verified running terminal.", status: 409) }
        let state = try await cmux.request("surface.input_state", params: ["workspace_id": .string(workspace), "surface_id": .string(surface)])
        // Cross-validate the binding, not the agent badge: the badge is a sidebar-fold derivative
        // that can stay false while the hook record that authorizes a send is alive (observed after
        // a journal fold outage). cmux's own send still checks its hook record and refuses a terminal
        // whose record is gone, so a broken badge must not turn a live conversation read-only.
        guard state["workspace_id"].string?.lowercased() == workspace.lowercased(), state["surface_id"].string?.lowercased() == surface.lowercased() else { throw BridgeError("stale_binding", "The agent's terminal binding changed. Refresh the task.", status: 409) }
        // The screen is the second check. A live agent's terminal renders its prompt box (`empty`,
        // `draft` or `dialog`), so one of those proves the agent is on screen even when the sidebar
        // fold is broken. Anything else — `unknown`, or a response that omits the screen state — could
        // be the bare shell left by an agent that died without a SessionEnd hook, so it fails closed.
        let promptOnScreen = ["empty", "draft", "dialog"].contains(state["state"].string)
        if state["terminal"].bool == false || (state["agent"].bool != true && !promptOnScreen) {
            throw BridgeError("stale_binding", "The agent has exited this terminal. Reopen the conversation.", status: 409)
        }
        // Interrupt does not paste over a draft and must remain available during a dialog.
        if requiresEmptyPrompt, state["blocks_typing"].bool == true { throw BridgeError("input_busy", "The desktop has a draft or an open question. Resolve it first.", status: 409) }
        try await access?.require(.conversationControl, workspace: workspace)
        guard records[id]?.descriptor.workspaceID == workspace, records[id]?.descriptor.surfaceID == surface, records[id]?.descriptor.writable == true else { throw BridgeError("stale_binding", "The terminal changed while authorizing the action.", status: 409) }
        return value
    }
    private func authorizedRecord(_ id: String, capability: ClientCapability, discovered: Bool = false, access: SessionAccess?) async throws -> Record {
        if access != nil, !discovered { _ = try await sessions() }
        let value = try await record(id)
        try await access?.require(capability, workspace: value.descriptor.workspaceID)
        guard records[id]?.descriptor.workspaceID == value.descriptor.workspaceID, records[id]?.descriptor.surfaceID == value.descriptor.surfaceID else { throw BridgeError("stale_binding", "The session changed while authorizing access.", status: 409) }
        return value
    }
    private func recheck(_ record: Record, capability: ClientCapability, access: SessionAccess?) async throws { try await recheck(record, capabilities: [capability], access: access) }
    private func recheck(_ record: Record, capabilities: [ClientCapability], access: SessionAccess?) async throws {
        try await access?.require(capabilities, workspace: record.descriptor.workspaceID)
        let current = records[record.descriptor.id]?.descriptor
        guard current?.workspaceID == record.descriptor.workspaceID, current?.surfaceID == record.descriptor.surfaceID else { throw BridgeError("stale_binding", "The resource binding changed during its read.", status: 409) }
    }
    private func allowedTranscript(_ path: String?) -> String? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension == "jsonl", transcriptRoots.contains(where: { url.path.hasPrefix($0.path + "/") }) else { return nil }
        return url.path
    }
    private func hasCmuxBinding(_ item: JSONValue) -> Bool {
        guard let workspace = item["workspace_id"].string, let surface = item["surface_id"].string else { return false }
        return !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Legacy injected journals remain a scoped test/migration seam; production uses the shared ledger.
    public func operationStatus(id: UUID, access: SessionAccess? = nil) async throws -> OperationStatus {
        if let journal {
            let principal = access?.clientID ?? "legacy"
            guard let entry = try journal.entry(id: id, principal: principal) else { throw BridgeError("operation_not_found", "No operation record was found.", status: 404) }
            try await access?.require(entry.capability, workspace: entry.workspace)
            return entry.status
        }
        guard let entry = try await mutations.operation(clientID: access?.clientID ?? "owner", operationID: id) else { throw BridgeError("operation_not_found", "No operation record was found.", status: 404) }
        try await access?.require(entry.capability, workspace: entry.workspaceID)
        return OperationStatus(operationID: id, state: entry.receipt == nil ? .outcomeUnknown : .accepted, recordedAt: entry.recordedAt ?? .distantPast)
    }
    private func existing(_ id: UUID, signature: String, legacySignature: String? = nil, access: SessionAccess?) async throws -> MutationReceipt? {
        if let legacySignature, let journal {
            let principal = access?.clientID ?? "legacy"
            guard let entry = try journal.existing(id: id, signature: legacySignature, principal: principal) else { return nil }
            try await access?.require(entry.capability, workspace: entry.workspace)
            guard entry.state == .accepted else { throw BridgeError("outcome_unknown", "Inspect the task before repeating this operation.", status: 409) }
            return MutationReceipt(operationID: id, accepted: true)
        }
        let alternatives = legacySignature.map { [MutationJournal.fingerprint($0)] } ?? []
        guard let entry = try await mutations.prior(clientID: access?.clientID ?? "owner", operationID: id, fingerprint: signature, alternativeFingerprints: alternatives) else { return nil }
        return try await checkedReceipt(entry, access: access)
    }
    private func begin(_ id: UUID, signature: String, workspace: String?, capability: ClientCapability, legacySignature: String? = nil, access: SessionAccess?) async throws -> MutationReceipt? {
        guard let workspace else { throw BridgeError("stale_binding", "Mutation target has no workspace.", status: 409) }
        if let legacySignature, journal != nil {
            try journal!.begin(id: id, signature: legacySignature, principal: access?.clientID ?? "legacy", resource: signature, workspace: workspace, capability: capability)
            return nil
        }
        guard let prior = try await mutations.begin(clientID: access?.clientID ?? "owner", operationID: id, fingerprint: signature,
                                                    workspaceID: workspace, capability: capability) else { return nil }
        return try await checkedReceipt(prior, access: access)
    }
    private func complete(_ id: UUID, access: SessionAccess?) async throws -> MutationReceipt {
        if journal != nil {
            do { return try journal!.complete(id: id) }
            catch { throw BridgeError("outcome_unknown", "The receipt could not be saved. Inspect the task.", status: 504) }
        }
        return try await mutations.complete(clientID: access?.clientID ?? "owner", operationID: id)
    }
    private func checkedReceipt(_ entry: MutationLedger.Entry, access: SessionAccess?) async throws -> MutationReceipt {
        try await access?.require(entry.capability, workspace: entry.workspaceID)
        guard let receipt = entry.receipt else { throw BridgeError("outcome_unknown", "Inspect the task before repeating this operation.", status: 409) }
        return receipt
    }
    private func validateMutationBinding(_ session: SessionDescriptor, access: SessionAccess?) async throws {
        try await access?.require(.conversationControl, workspace: session.workspaceID)
        let current = records[session.id]?.descriptor
        guard current?.writable == true, current?.workspaceID == session.workspaceID, current?.surfaceID == session.surfaceID else {
            throw BridgeError("stale_binding", "The terminal changed before executing the action.", status: 409)
        }
    }
    private func mutationError(_ error: any Error) -> BridgeError {
        (error as? BridgeError) ?? BridgeError("outcome_unknown", "The result is unknown; inspect the task before trying again.", status: 504)
    }
}
