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
    private var operations: [UUID: (String, MutationReceipt?)] = [:]
    private var failedOperations = Set<UUID>()
    private var liveBindings: [String: JSONValue] = [:]
    private var eventBoot: String?
    private var eventSequence: Int?

    public init(cmux: any CmuxControlling, home: URL, transcriptRoots: [URL]) {
        self.cmux = cmux; self.transcriptRoots = transcriptRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.files = ProjectFilePolicy(home: home)
    }

    public func status() async throws -> JSONValue {
        _ = try await cmux.request("system.ping", params: [:])
        let caps = try await cmux.request("system.capabilities", params: [:])
        return .object(["protocol": .string("cmux-remote/1"), "cmux": caps, "history_source": .string("local_transcript"), "preview_fidelity": .string("screen_best_effort")])
    }
    public func workspaces() async throws -> JSONValue { try await cmux.request("workspace.list", params: [:]) }
    public func feed() async throws -> JSONValue { try await cmux.request("feed.list", params: [:]) }

    public func sessions() async throws -> [SessionDescriptor] {
        let vault = try await cmux.request("vault.sessions", params: ["limit": .number(200)])
        let dump = try? await cmux.request("chat.sessions.dump", params: [:])
        let authoritativeIDs = Set((dump?["sessions"].array ?? []).compactMap { $0["session_id"].string })
        var discovered: [String: Record] = [:]
        for item in vault["sessions"].array ?? [] {
            guard let id = item["session_id"].string, let agent = item["agent"].string,
                  ["claude", "codex"].contains(agent) else { continue }
            let path = allowedTranscript(item["file"].string)
            let descriptor = SessionDescriptor(id: id, agent: agent, title: item["title"].string ?? id, cwd: item["cwd"].string, state: item["status"].string ?? "unknown")
            discovered[id] = Record(descriptor: descriptor, transcript: path)
        }
        for item in dump?["sessions"].array ?? [] {
            guard let id = item["session_id"].string, let agent = item["agent"].string, ["claude", "codex"].contains(agent) else { continue }
            var record = discovered[id] ?? Record(descriptor: SessionDescriptor(id: id, agent: agent, title: id, cwd: item["cwd"].string), transcript: allowedTranscript(item["transcript_path"].string))
            record.descriptor.workspaceID = item["workspace_id"].string
            record.descriptor.surfaceID = item["surface_id"].string
            record.descriptor.state = item["state"].string ?? "unknown"
            discovered[id] = record
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

    public func history(id: String, beforeSeq: Int?, limit: Int) async throws -> ConversationSnapshot {
        let record = try await record(id)
        guard let path = record.transcript else { throw BridgeError("history_unavailable", "No readable conversation record is available.", status: 404) }
        let reader = reader; let agent = record.descriptor.agent
        return try await reader.history(path: path, agent: agent, beforeSeq: beforeSeq, limit: limit)
    }

    public func preview(id: String) async throws -> PreviewSnapshot {
        _ = try await sessions()
        let record = try await record(id)
        guard record.descriptor.writable, let surface = record.descriptor.surfaceID else { return PreviewSnapshot(text: nil, available: false) }
        let snapshot = try await cmux.request("surface.read_text", params: ["surface_id": .string(surface)])
        let lines = (snapshot["text"].string ?? "").components(separatedBy: .newlines)
        let text = AgentChatProseScreenExtractor().extract(lines: lines, agentKind: ChatAgentKind(source: record.descriptor.agent))
        return PreviewSnapshot(text: text, available: true)
    }

    public func send(id: String, request: SendRequest) async throws -> MutationReceipt {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.text.utf8.count <= 65_536 else { throw BridgeError("invalid_input", "Enter a prompt within the size limit.") }
        let signature = "send:\(id):\(request.text)"
        if let receipt = try existing(request.operationID, signature: signature) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: true)
        try begin(request.operationID, signature: signature)
        do {
            _ = try await cmux.request("mobile.chat.send", params: ["session_id": .string(session.id), "text": .string(request.text)])
            return complete(request.operationID)
        } catch { failedOperations.insert(request.operationID); throw mutationError(error) }
    }

    public func interrupt(id: String, request: InterruptRequest) async throws -> MutationReceipt {
        let signature = "interrupt:\(id):\(request.hard)"
        if let receipt = try existing(request.operationID, signature: signature) { return receipt }
        let session = try await verifiedBinding(id, requiresEmptyPrompt: false)
        try begin(request.operationID, signature: signature)
        do {
            _ = try await cmux.request("mobile.chat.interrupt", params: ["session_id": .string(session.id), "hard": .bool(request.hard)])
            return complete(request.operationID)
        } catch { failedOperations.insert(request.operationID); throw mutationError(error) }
    }

    public func reply(requestID: String, body: JSONValue) async throws -> MutationReceipt {
        guard let rawID = body["operation_id"].string, let operation = UUID(uuidString: rawID), let kind = body["kind"].string else { throw BridgeError("invalid_input", "A decision identity and kind are required.") }
        let serialized = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        let signature = "reply:\(requestID):\(serialized)"
        if let receipt = try existing(operation, signature: signature) { return receipt }
        let items = try await feed()["items"].array ?? []
        guard let pending = items.first(where: { $0["request_id"].string == requestID && $0["status"].string == "pending" }), pending["kind"].string == kind else { throw BridgeError("request_expired", "This request is no longer waiting for a decision.", status: 409) }
        let method: String; var params: [String: JSONValue] = ["request_id": .string(requestID)]
        switch kind {
        case "permissionRequest":
            guard let mode = body["mode"].string, ["once", "deny"].contains(mode) else { throw BridgeError("invalid_input", "Choose allow once or deny.") }
            method = "feed.permission.reply"; params["mode"] = .string(mode)
        case "exitPlan":
            guard let mode = body["mode"].string, ["manual", "deny"].contains(mode) else { throw BridgeError("invalid_input", "Choose manual or deny.") }
            method = "feed.exit_plan.reply"; params["mode"] = .string(mode)
        case "question":
            guard let choices = body["selections"].array, choices.allSatisfy({ $0.string != nil }) else { throw BridgeError("invalid_input", "Choose an answer.") }
            method = "feed.question.reply"; params["selections"] = .array(choices)
        default: throw BridgeError("unsupported", "cmux does not expose this decision.", status: 422)
        }
        try begin(operation, signature: signature)
        do { _ = try await cmux.request(method, params: params); return complete(operation) }
        catch { failedOperations.insert(operation); throw mutationError(error) }
    }

    public func file(id: String, path: String) async throws -> TextFileSnapshot {
        guard let cwd = try await record(id).descriptor.cwd else { throw BridgeError("project_unavailable", "This conversation has no project directory.", status: 404) }
        let file = try files.resolve(root: cwd, relativePath: path)
        let data = try Data(contentsOf: file)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw BridgeError("unsupported_file", "The initial preview supports UTF-8 text files.", status: 415) }
        return TextFileSnapshot(path: path, text: text, truncated: false)
    }
    public func changes(id: String) async throws -> JSONValue {
        let cwd = try await project(id)
        let output = try await GitReader().run(directory: cwd, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=normal"])
        return .object(["entries": .array(output.split(separator: "\0").map { .string(String($0)) })])
    }
    public func diff(id: String, path: String?) async throws -> TextFileSnapshot {
        let cwd = try await project(id)
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
        guard !allowed.isEmpty else { return TextFileSnapshot(path: path ?? "", text: "", truncated: false) }
        let arguments = ["diff", "--no-ext-diff", "--no-textconv", "HEAD", "--"] + allowed
        let text = try await GitReader().run(directory: cwd, arguments: arguments)
        return TextFileSnapshot(path: path ?? "", text: text, truncated: false)
    }

    private func project(_ id: String) async throws -> String {
        guard let cwd = try await record(id).descriptor.cwd, cwd != "/" else { throw BridgeError("project_unavailable", "This conversation has no project directory.", status: 404) }
        return try files.projectRoot(cwd).path
    }
    private func record(_ id: String) async throws -> Record {
        if records[id] == nil { _ = try await sessions() }
        guard let record = records[id] else { throw BridgeError("session_not_found", "This conversation is no longer available.", status: 404) }
        return record
    }
    private func verifiedBinding(_ id: String, requiresEmptyPrompt: Bool) async throws -> SessionDescriptor {
        _ = try await sessions()
        let value = try await record(id).descriptor
        guard value.writable, let surface = value.surfaceID, let workspace = value.workspaceID else { throw BridgeError("read_only", "This historical conversation has no verified running terminal.", status: 409) }
        let state = try await cmux.request("surface.input_state", params: ["workspace_id": .string(workspace), "surface_id": .string(surface)])
        guard state["agent"].bool == true, state["workspace_id"].string?.lowercased() == workspace.lowercased(), state["surface_id"].string?.lowercased() == surface.lowercased() else { throw BridgeError("stale_binding", "The agent's terminal binding changed. Refresh the task.", status: 409) }
        // Interrupt does not paste over a draft and must remain available during a dialog.
        if requiresEmptyPrompt, state["blocks_typing"].bool == true { throw BridgeError("input_busy", "The desktop has a draft or an open question. Resolve it first.", status: 409) }
        return value
    }
    private func allowedTranscript(_ path: String?) -> String? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension == "jsonl", transcriptRoots.contains(where: { url.path.hasPrefix($0.path + "/") }) else { return nil }
        return url.path
    }
    private func existing(_ id: UUID, signature: String) throws -> MutationReceipt? {
        guard let entry = operations[id] else { return nil }
        guard entry.0 == signature else { throw BridgeError("operation_conflict", "This operation identity was already used for different input.", status: 409) }
        guard !failedOperations.contains(id), let receipt = entry.1 else { throw BridgeError("outcome_unknown", "Inspect the task before repeating this operation.", status: 409) }
        return receipt
    }
    private func begin(_ id: UUID, signature: String) throws {
        // The actor may suspend during fresh binding checks. Claim again before I/O.
        guard operations[id] == nil else { throw BridgeError("operation_conflict", "This operation is already in progress.", status: 409) }
        guard operations.count < 512 else { throw BridgeError("receipt_capacity", "Restart the Bridge after checking pending operations.", status: 503) }
        operations[id] = (signature, nil)
    }
    private func complete(_ id: UUID) -> MutationReceipt {
        let receipt = MutationReceipt(operationID: id, accepted: true)
        operations[id]?.1 = receipt
        return receipt
    }
    private func mutationError(_ error: any Error) -> BridgeError {
        (error as? BridgeError) ?? BridgeError("outcome_unknown", "The result is unknown; inspect the task before trying again.", status: 504)
    }
}
