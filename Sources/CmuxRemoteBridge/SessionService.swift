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
    private let reader = TranscriptReader()
    private var records: [String: Record] = [:]
    private var transcriptTails: [String: (size: Int, cwd: String?, lastMessage: Date?)] = [:]
    private let mutations: MutationLedger
    private var journal: MutationJournal?
    private var liveBindings: [String: JSONValue] = [:]
    private var eventBoot: String?
    private var eventSequence: Int?

    public init(cmux: any CmuxControlling, home: URL, transcriptRoots: [URL], mutations: MutationLedger? = nil, journal: MutationJournal? = nil) {
        self.cmux = cmux; self.transcriptRoots = transcriptRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.files = ProjectFilePolicy(home: home); self.mutations = mutations ?? MutationLedger(); self.journal = journal
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
    private func transcriptFacts(_ path: String) -> (cwd: String?, updatedAt: Date?)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0 else { return nil }
        let modified = attributes[.modificationDate] as? Date
        if let cached = transcriptTails[path], cached.size == size { return (cached.cwd, cached.lastMessage ?? modified) }
        let cwd = TranscriptWorkingDirectory().read(path: path, size: size)
        let lastMessage = TranscriptActivity().lastMessage(path: path, size: size)
        if transcriptTails.count >= 512 { transcriptTails.removeAll() }
        transcriptTails[path] = (size, cwd, lastMessage); return (cwd, lastMessage ?? modified)
    }
    public func sessions() async throws -> [SessionDescriptor] {
        let vault = try await cmux.request("vault.sessions", params: ["limit": .number(200)])
        let dump = try? await cmux.request("chat.sessions.dump", params: [:])
        let authoritativeIDs = Set((dump?["sessions"].array ?? []).compactMap { $0["session_id"].string })
        // Vault includes sessions started outside cmux. It enriches known bindings,
        // never establishes which conversations belong in this companion.
        let registeredIDs = Set((dump?["sessions"].array ?? []).filter { hasCmuxBinding($0) }.compactMap { $0["session_id"].string })
        let hookedIDs = Set(liveBindings.filter { hasCmuxBinding($0.value) }.keys)
        let cmuxIDs = registeredIDs.union(hookedIDs)
        var discovered: [String: Record] = [:]
        for item in vault["sessions"].array ?? [] {
            guard let id = item["session_id"].string, cmuxIDs.contains(id), let agent = item["agent"].string,
                  ["claude", "codex"].contains(agent) else { continue }
            let path = allowedTranscript(item["file"].string)
            let descriptor = SessionDescriptor(id: id, agent: agent, title: item["title"].string ?? id, cwd: item["cwd"].string, state: item["status"].string ?? "unknown")
            discovered[id] = Record(descriptor: descriptor, transcript: path)
        }
        for item in dump?["sessions"].array ?? [] {
            guard let id = item["session_id"].string, cmuxIDs.contains(id), let agent = item["agent"].string, ["claude", "codex"].contains(agent) else { continue }
            var record = discovered[id] ?? Record(descriptor: SessionDescriptor(id: id, agent: agent, title: id, cwd: item["cwd"].string), transcript: allowedTranscript(item["transcript_path"].string))
            record.descriptor.workspaceID = item["workspace_id"].string
            record.descriptor.surfaceID = item["surface_id"].string
            record.descriptor.state = item["state"].string ?? "unknown"
            discovered[id] = record
        }
        for (id, record) in discovered {
            guard let path = record.transcript, let facts = transcriptFacts(path) else { continue }
            let old = record.descriptor
            discovered[id]?.descriptor = SessionDescriptor(id: old.id, agent: old.agent, title: old.title, cwd: facts.cwd ?? old.cwd, workspaceID: old.workspaceID,
                                                           surfaceID: old.surfaceID, state: old.state, updatedAt: facts.updatedAt)
        }
        records = discovered
        for (id, event) in liveBindings {
            guard records[id] != nil else { continue }
            // Fresh cmux process-exit state outranks an older retained hook binding.
            guard !authoritativeIDs.contains(id) || event["state"].string == "ended" else { continue }
            records[id]?.descriptor.workspaceID = event["workspace_id"].string
            records[id]?.descriptor.surfaceID = event["surface_id"].string
            records[id]?.descriptor.state = event["state"].string ?? "unknown"
        }
        return records.values.map(\.descriptor).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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

    public func history(id: String, beforeSeq: Int?, limit: Int, access: SessionAccess? = nil) async throws -> ConversationSnapshot {
        let record = try await authorizedRecord(id, capability: .conversationRead, access: access)
        guard let path = record.transcript else { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        let reader = reader; let agent = record.descriptor.agent
        let result = try await reader.history(path: path, agent: agent, beforeSeq: beforeSeq, limit: limit,
                                             allowsUncreatedTranscript: record.descriptor.writable)
        try await recheck(record, capability: .conversationRead, access: access)
        return result
    }

    /// Returns a bounded, revision-bound page from an authorized session's tool record.
    public func toolText(id: String, messageID: String, generation: String, field: String,
                         offset: Int, contentID: String?, limit: Int, access: SessionAccess? = nil) async throws -> ToolTextPage {
        let record = try await authorizedRecord(id, capability: .conversationRead, access: access)
        guard let path = record.transcript else { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        let result = try await reader.toolText(path: path, agent: record.descriptor.agent, messageID: messageID,
                                             generation: generation, field: field, offset: offset, contentID: contentID, limit: limit)
        try await recheck(record, capability: .conversationRead, access: access)
        return result
    }

    /// Reads only a transcript-bound image; project bytes additionally require project-read authority.
    public func image(id: String, referenceID: String, generation: String, access: SessionAccess? = nil) async throws -> Data {
        let record = try await authorizedRecord(id, capability: .conversationRead, access: access)
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

    public func preview(id: String, access: SessionAccess? = nil) async throws -> PreviewSnapshot {
        _ = try await sessions()
        let record = try await authorizedRecord(id, capability: .conversationRead, access: access)
        guard record.descriptor.writable, let surface = record.descriptor.surfaceID else { return PreviewSnapshot(text: nil, available: false) }
        let snapshot = try await cmux.request("surface.read_text", params: ["surface_id": .string(surface)])
        let lines = (snapshot["text"].string ?? "").components(separatedBy: .newlines)
        let text = AgentChatProseScreenExtractor().extract(lines: lines, agentKind: ChatAgentKind(source: record.descriptor.agent))
        try await recheck(record, capability: .conversationRead, access: access)
        return PreviewSnapshot(text: text, available: true)
    }

    public func send(id: String, request: SendRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        guard (!request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !request.attachments.isEmpty), request.text.utf8.count <= 65_536 else { throw BridgeError("invalid_input", "Enter a prompt within the size limit.") }
        let attachments = try ChatImagePolicy().attachments(request.attachments)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let legacySignature = request.attachments.isEmpty ? "send:\(id):\(request.text)" : "send:\(id):\(String(decoding: try encoder.encode(request), as: UTF8.self))"
        let payload: JSONValue = request.attachments.isEmpty ? .string(request.text) : .object(["text": .string(request.text), "attachments": try JSONDecoder().decode(JSONValue.self, from: encoder.encode(request.attachments))])
        let signature = try MutationLedger.fingerprint(action: "send", resource: id, payload: payload)
        if let receipt = try await existing(request.operationID, signature: signature, legacySignature: legacySignature, access: access) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: true, access: access)
        if let receipt = try await begin(request.operationID, signature: signature, workspace: session.workspaceID, capability: .conversationControl, legacySignature: legacySignature, access: access) { return receipt }
        try await validateMutationBinding(session, access: access)
        do {
            var params: [String: JSONValue] = ["session_id": .string(session.id), "text": .string(request.text), "operation_id": .string(request.operationID.uuidString), "backend_operation_key": .string(IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + request.operationID.uuidString).utf8))), "workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)]
            if !attachments.isEmpty { params["attachments"] = .array(attachments) }
            let result = try await cmux.request("mobile.chat.send", params: params)
            guard result["submitted"].bool != false else { throw BridgeError("outcome_unknown", "cmux did not confirm prompt submission; inspect its draft before retrying.", status: 409) }
            return try await complete(request.operationID, access: access)
        } catch { journal?.uncertain(id: request.operationID); throw mutationError(error) }
    }

    public func interrupt(id: String, request: InterruptRequest, access: SessionAccess? = nil) async throws -> MutationReceipt {
        let legacySignature = "interrupt:\(id):\(request.hard)"
        let signature = try MutationLedger.fingerprint(action: "interrupt", resource: id, payload: .bool(request.hard))
        if let receipt = try await existing(request.operationID, signature: signature, legacySignature: legacySignature, access: access) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: false, access: access)
        if let receipt = try await begin(request.operationID, signature: signature, workspace: session.workspaceID, capability: .conversationControl, legacySignature: legacySignature, access: access) { return receipt }
        try await validateMutationBinding(session, access: access)
        do {
            let result = try await cmux.request("mobile.chat.interrupt", params: ["session_id": .string(session.id), "hard": .bool(request.hard), "operation_id": .string(request.operationID.uuidString), "backend_operation_key": .string(IdentityCryptography().digest(Data(((access?.clientID ?? "owner") + ":" + request.operationID.uuidString).utf8))), "workspace_id": .string(session.workspaceID!), "surface_id": .string(session.surfaceID!)])
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

    public func file(id: String, path: String, access: SessionAccess? = nil) async throws -> TextFileSnapshot {
        let record = try await authorizedRecord(id, capability: .projectRead, access: access)
        guard let cwd = record.descriptor.cwd else { throw BridgeError("project_unavailable", "This conversation has no project directory.", status: 404) }
        let file = try files.resolve(root: cwd, relativePath: path)
        let data = try Data(contentsOf: file)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw BridgeError("unsupported_file", "The initial preview supports UTF-8 text files.", status: 415) }
        try await recheck(record, capability: .projectRead, access: access)
        return TextFileSnapshot(path: path, text: text, truncated: false)
    }
    public func changes(id: String, access: SessionAccess? = nil) async throws -> JSONValue {
        let record = try await authorizedRecord(id, capability: .projectRead, access: access)
        let cwd = try projectRoot(record)
        let output = try await GitReader().run(directory: cwd, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=normal"])
        try await recheck(record, capability: .projectRead, access: access)
        return .object(["entries": .array(output.split(separator: "\0").map { .string(String($0)) })])
    }
    public func diff(id: String, path: String?, access: SessionAccess? = nil) async throws -> TextFileSnapshot {
        let record = try await authorizedRecord(id, capability: .projectRead, access: access)
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
        guard state["agent"].bool == true, state["workspace_id"].string?.lowercased() == workspace.lowercased(), state["surface_id"].string?.lowercased() == surface.lowercased() else { throw BridgeError("stale_binding", "The agent's terminal binding changed. Refresh the task.", status: 409) }
        // Interrupt does not paste over a draft and must remain available during a dialog.
        if requiresEmptyPrompt, state["blocks_typing"].bool == true { throw BridgeError("input_busy", "The desktop has a draft or an open question. Resolve it first.", status: 409) }
        try await access?.require(.conversationControl, workspace: workspace)
        guard records[id]?.descriptor.workspaceID == workspace, records[id]?.descriptor.surfaceID == surface, records[id]?.descriptor.writable == true else { throw BridgeError("stale_binding", "The terminal changed while authorizing the action.", status: 409) }
        return value
    }
    private func authorizedRecord(_ id: String, capability: ClientCapability, access: SessionAccess?) async throws -> Record {
        if access != nil { _ = try await sessions() }
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
