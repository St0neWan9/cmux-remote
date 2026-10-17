import Foundation
import CmuxRemoteCore

/// Adapts one local daemon to existing phone domain operations, without desktop/UI coupling.
public actor TuiControlAdapter: CmuxControlling {
    private let client: any TuiResourceRequesting
    private let transcripts: TuiTranscriptLocator
    private let attachments: TuiAttachmentStore?
    private let decisions: MutationLedger
    private let archive: TuiBindingRepository?
    private var archiveLoaded = false
    private var catalog: [String: TuiSessionSnapshot.Binding] = [:]
    private var pending: [String: TuiPendingDecision] = [:]
    private var pinnedIdentity: String?
    private var knownConversations: Set<String> = []
    private var knownSurfaces: Set<String> = []
    private var knownWorkspaces: Set<String> = []
    private let prompt = TuiPromptSafety()
    /// The last prompt text the phone wrote per conversation; an interrupted Agent may put it back in its input.
    private var lastSent: [String: String] = [:]
    private var hooks = TuiHookStates()
    /// The journal position after the last folded hook; nil until the first read and after a failed one.
    private var journalCursor: JSONValue?
    private let restoreChecks: Int
    private let journalWindow: UInt64
    private let restoreInterval: Duration
    public init(client: any TuiResourceRequesting, transcripts: TuiTranscriptLocator, attachments: TuiAttachmentStore? = nil, decisions: MutationLedger = MutationLedger(), archive: TuiBindingRepository? = nil,
                restoreChecks: Int = 8, restoreInterval: Duration = .milliseconds(150), journalWindow: UInt64 = 20_000) {
        self.client = client; self.transcripts = transcripts; self.attachments = attachments; self.decisions = decisions; self.archive = archive
        self.restoreChecks = restoreChecks; self.restoreInterval = restoreInterval; self.journalWindow = journalWindow
    }
    public func identity() -> String? { pinnedIdentity }
    public func ownsDecision(_ id: String) -> Bool { pending[id] != nil }
    public func ownsConversation(_ id: String) -> Bool { knownConversations.contains(id) }
    public func ownsSurface(_ id: String) -> Bool { knownSurfaces.contains(id.lowercased()) }
    public func ownsWorkspace(_ id: String) -> Bool { knownWorkspaces.contains(id.lowercased()) }
    public func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping":
            _ = try await snapshot(); return .object(["backend": .string("cmux-tui")])
        case "system.capabilities":
            return .object(["backend": .string("cmux-tui"), "protocol": .string("cmux.protocol/2"), "attachments": .bool(attachments != nil), "feed_decisions": .bool(true), "native_mirror": .bool(false)])
        case "workspace.list": return .object(["workspaces": .array(try await snapshot().workspaces)])
        case "vault.sessions", "chat.sessions.dump":
            let current = try await snapshot()
            let liveIDs = Set(current.bindings.map(\.id))
            let activity = await hookActivity(current)
            let bindings = catalog.values.sorted { $0.id < $1.id }
            let paths = method == "vault.sessions" ? try transcripts.locate(Array(bindings)) : [:]
            var rows: [JSONValue] = []
            for binding in bindings {
                var row = descriptor(binding)
                // An Agent the daemon has not re-registered after a resume, on a terminal that is still running, is a
                // live conversation rather than a finished one; only a terminal that is gone makes it historical.
                var revived = false, promptKnown: Bool?
                if !liveIDs.contains(binding.id) {
                    // A running terminal only means the Agent is still there when its own prompt is on screen; the
                    // shell that replaced it would accept the phone's text as a command, so that case is resumable.
                    let running = current.runningTerminals.contains(binding.surfaceID)
                    let promptKnown = running ? await showsAgentPrompt(current, binding: binding) : nil
                    revived = running && promptKnown == true
                    if !revived { row["state"] = .string("ended"); row["status"] = .string("ended") }
                }
                if liveIDs.contains(binding.id) || revived, let state = activity[binding.providerSession] { row["state"] = .string(state); row["status"] = .string(state) }
                else if revived { row["state"] = .string("idle"); row["status"] = .string("idle") }
                // A conversation that can be reopened says so, so the phone offers to resume instead of a lock.
                if !liveIDs.contains(binding.id), !revived {
                    let resumable = await resumableBinding(id: binding.id, in: current, promptKnown: promptKnown)
                    if resumable != nil { row["resumable"] = .bool(true) }
                }
                // An interrupted Claude turn sends no Stop hook, so its hooks still say working; Claude Code marks
                // itself idle in the terminal title with `✳` (a turn in progress shows a spinner glyph instead).
                if liveIDs.contains(binding.id), binding.provider == "claude", row["state"]?.string == "working",
                   current.terminalTitles[binding.terminal]?.hasPrefix("✳") == true {
                    row["state"] = .string("idle"); row["status"] = .string("idle")
                }
                if let path = paths[binding.id] {
                    row["file"] = .string(path)
                }
                rows.append(.object(row))
            }
            return .object(["sessions": .array(rows), "discovery_limit": .number(200)])
        case "feed.list":
            let current = try await snapshot(); var next: [String: TuiPendingDecision] = [:]
            for binding in current.bindings where binding.state == "needs_input" {
                let screen = try await client.resource("terminal.screen.read", params: current.selectors(binding), idempotencyKey: nil)
                if let decision = TuiDecisionParser().permission(snapshot: current, binding: binding, screen: screen),
                   let operation = UUID(uuidString: String(decision.id.dropFirst("tui-decision:".count))),
                   try await decisions.scopedOperation(clientID: "tui_decision", operationID: operation) == nil { next[decision.id] = decision }
            }
            pending = next
            return .object(["items": .array(next.values.sorted { $0.id < $1.id }.map(\.payload))])
        case "feed.permission.reply":
            guard let id = params["request_id"]?.string, let original = pending[id], let mode = params["mode"]?.string, ["once", "deny"].contains(mode),
                  let operation = UUID(uuidString: String(id.dropFirst("tui-decision:".count))) else { throw BridgeError("request_expired", "This daemon permission request is no longer available.", status: 409) }
            let current = try await snapshot()
            guard current.generation == original.generation, let binding = current.bindings.first(where: { $0.id == original.binding.id }), binding == original.binding else { throw stale() }
            let screen = try await client.resource("terminal.screen.read", params: current.selectors(binding), idempotencyKey: nil)
            guard let fresh = TuiDecisionParser().permission(snapshot: current, binding: binding, screen: screen), fresh.id == original.id else { throw BridgeError("request_expired", "The permission screen changed before the decision.", status: 409) }
            let fingerprint = try MutationLedger.fingerprint(action: "tui-permission", resource: id, payload: .string(mode))
            if let prior = try await decisions.begin(clientID: "tui_decision", operationID: operation, fingerprint: fingerprint, workspaceID: binding.workspaceID, capability: .feedReply) {
                guard prior.receipt != nil else { throw BridgeError("outcome_unknown", "The previous decision is not confirmed; inspect the Agent.", status: 409) }
                return .object(["delivered": .bool(true)])
            }
            var fields = current.selectors(binding); fields["keys"] = .array((mode == "once" ? fresh.allowKeys : ["escape"]).map(JSONValue.string)); fields["expected_revision"] = .string(current.revision)
            try await effect("terminal.input.keys", fields: fields, key: "cmux-remote:decision:" + operation.uuidString.lowercased(), generation: current.generation)
            _ = try await decisions.complete(clientID: "tui_decision", operationID: operation); pending[id] = nil
            return .object(["delivered": .bool(true)])
        case "conversation.image.read":
            guard let id = params["session_id"]?.string, knownConversations.contains(id), let path = params["path"]?.string else { throw stale() }
            let data = try attachments?.image(conversation: id, path: path)
            return .object(["data_b64": data.map { .string($0.base64EncodedString()) } ?? .null])
        case "surface.read_text", "surface.input_state":
            let current = try await snapshot()
            guard let id = params["surface_id"]?.string?.lowercased(), let binding = activeBinding(surfaceID: id, in: current),
                  params["workspace_id"]?.string.map({ $0.lowercased() == binding.workspaceID }) != false else { throw stale() }
            let screen = try await client.resource("terminal.screen.read", params: current.selectors(binding), idempotencyKey: nil)
            guard let text = screen["text"].string, text.utf8.count <= 1_048_576 else { throw BridgeError("invalid_response", "The daemon screen is invalid.", status: 502) }
            if method == "surface.read_text" { return .object(["text": .string(text)]) }
            return .object(["workspace_id": .string(binding.workspaceID), "surface_id": .string(binding.surfaceID), "agent": .bool(true), "terminal": .bool(true), "blocks_typing": .bool(!prompt.isEmpty(try await terminalState(current, binding: binding), provider: binding.provider)), "lifecycle": .string(binding.state)])
        case "surface.create":
            // Session starting: a new terminal tab in the workspace's active pane running a fixed agent command.
            // The daemon keeps the session's focused workspace and pane; only that pane's visible tab changes.
            guard params["type"]?.string == "terminal", let workspaceID = params["workspace_id"]?.string?.lowercased(),
                  let cwd = params["working_directory"]?.string, cwd.hasPrefix("/"),
                  let agent = params["launch_agent"]?.string.flatMap(LaunchAgent.init(rawValue:)),
                  let key = params["operation_key"]?.string, !key.isEmpty, key.utf8.count <= 128 else { throw BridgeError("invalid_input", "Invalid daemon terminal request.") }
            let commandLine = AgentCommandLine()
            let prompt = try commandLine.validatedPrompt(params["launch_prompt"]?.string)
            let current = try await snapshot()
            guard let workspace = current.rawWorkspaces[workspaceID] else { throw stale() }
            var request = current.selectors()
            request["workspace"] = .string(workspace); request["cwd"] = .string(cwd); request["name"] = .string(agent.rawValue)
            // The daemon's `-lc` skips the interactive startup files where agents are often put on PATH. The owner's
            // interactive shell runs the agent as a typed command would, then stays open as a login shell.
            let shell = Self.loginShell()
            request["argv"] = .array([.string(shell), .string("-ic"), .string(commandLine.line(agent, prompt: prompt) + "; exec " + commandLine.quoted(shell) + " -l")])
            request["correlation_key"] = .string(key)
            let created = try await client.resource("workspace.run", params: request, idempotencyKey: key)
            guard let terminal = created["value"]["terminal_id"].string, (try? TuiResourceIdentity().validate(terminal, prefix: "term")) != nil else {
                throw BridgeError("outcome_unknown", "The daemon did not confirm the new terminal.", status: 409)
            }
            let surface = TuiResourceIdentity().uuid(machine: current.machine, session: current.session, resource: terminal)
            knownSurfaces.insert(surface)
            return .object(["surface_id": .string(surface)])
        case "mobile.chat.resume":
            // Reopening one Agent session in a new terminal: the conversation, its provider session and the directory
            // all come from this Bridge's own binding and the Agent's transcript, never from the caller.
            guard let id = params["session_id"]?.string, let key = params["operation_key"]?.string, !key.isEmpty, key.utf8.count <= 128 else {
                throw BridgeError("invalid_input", "A conversation and a stable operation identity are required.")
            }
            let current = try await snapshot()
            guard let found = await resumableBinding(id: id, in: current) else { throw stale() }
            let binding = found.binding
            var request = current.selectors()
            request["workspace"] = .string(binding.workspace); request["cwd"] = .string(found.cwd)
            request["name"] = .string(binding.provider)
            // The daemon's `-lc` skips the interactive startup files where agents are often put on PATH, so the owner's
            // interactive shell runs the resume as a typed command would, and a login shell stays open after it exits.
            let shell = Self.loginShell()
            guard let agent = LaunchAgent(rawValue: binding.provider) else { throw stale() }
            let line = agent.resumeCommand(sessionID: binding.providerSession)
            request["argv"] = .array([.string(shell), .string("-ic"), .string(line + "; exec " + AgentCommandLine().quoted(shell) + " -l")])
            request["correlation_key"] = .string(key)
            let created = try await client.resource("workspace.run", params: request, idempotencyKey: key)
            guard let terminal = created["value"]["terminal_id"].string, (try? TuiResourceIdentity().validate(terminal, prefix: "term")) != nil else {
                throw BridgeError("outcome_unknown", "The daemon did not confirm the reopened terminal.", status: 409)
            }
            knownSurfaces.insert(TuiResourceIdentity().uuid(machine: current.machine, session: current.session, resource: terminal))
            return .object(["surface_id": .string(TuiResourceIdentity().uuid(machine: current.machine, session: current.session, resource: terminal))])
        case "mobile.chat.send", "mobile.chat.interrupt":
            guard let id = params["session_id"]?.string, let operation = params["operation_id"]?.string, let operationUUID = UUID(uuidString: operation), let operationKey = params["backend_operation_key"]?.string, operationKey.count == 64, operationKey.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw BridgeError("invalid_input", "A stable conversation operation identity is required.")
            }
            let current = try await snapshot()
            guard let binding = activeBinding(id: id, in: current),
                  params["workspace_id"]?.string?.lowercased() == binding.workspaceID,
                  params["surface_id"]?.string?.lowercased() == binding.surfaceID else { throw stale() }
            if method == "mobile.chat.interrupt" {
                var request = current.selectors(binding); request["keys"] = .array([.string(params["hard"]?.bool == true ? "ctrl+c" : "escape")]); request["expected_revision"] = .string(current.revision)
                try await effect("terminal.input.keys", fields: request, key: "cmux-remote:interrupt:" + operationKey.lowercased(), generation: current.generation)
                hooks.interrupted(binding.providerSession)
                if let sent = lastSent.removeValue(forKey: binding.id) { await clearRestoredPrompt(sent, binding: binding, operationKey: operationKey) }
                return .object(["interrupted": .bool(true)])
            }
            let images = params["attachments"]?.array ?? []
            guard let text = params["text"]?.string, !text.isEmpty || !images.isEmpty, text.utf8.count <= 65_536,
                  text.unicodeScalars.allSatisfy({ $0.value >= 32 && !(127...159).contains($0.value) || $0 == "\n" || $0 == "\t" }) else {
                throw BridgeError("invalid_input", "Use bounded prompt text without terminal control characters.")
            }
            let (cleared, state) = try await clearPromptForSend(current, binding: binding, operationKey: operationKey)
            let paste = state.pasteEnabled
            guard paste || !text.contains("\n") else { throw unsupported() }
            let imagePaths: [String]
            if images.isEmpty { imagePaths = [] }
            else { guard let attachments else { throw unsupported() }; imagePaths = try attachments.save(images, conversation: binding.id, operation: operationUUID, storageKey: operationKey) }
            let content = (imagePaths + (text.isEmpty ? [] : [text])).joined(separator: " ")
            // Recheck binding/revision after screen/state reads; never retarget an old session.
            let final = try await snapshot()
            guard final.generation == cleared.generation, final.revision == cleared.revision,
                  stillBound(binding, in: final) else { throw stale() }
            var request = final.selectors(binding)
            request["text"] = .string((paste ? "\u{1b}[200~" + content + "\u{1b}[201~" : content) + "\r")
            request["expected_revision"] = .string(final.revision)
            try await effect("terminal.input.write", fields: request, key: "cmux-remote:send:" + operationKey.lowercased(), generation: final.generation)
            if lastSent.count >= 200, lastSent[binding.id] == nil { lastSent.removeAll() }
            lastSent[binding.id] = imagePaths.isEmpty ? text : nil
            return .object(["submitted": .bool(true)])
        default: throw unsupported()
        }
    }
    /// Folds agent hooks committed since the last read; an unreadable journal falls back to the daemon's own states.
    private func hookActivity(_ current: TuiSessionSnapshot) async -> [String: String] {
        let filter: JSONValue = .object(["kinds": .array([.string("agent.*")]), "max_sensitivity": .string("sensitive")])
        // Every read is its own daemon stream, addressed to the snapshot's machine and session.
        func params(_ cursor: JSONValue?) -> [String: JSONValue] {
            var fields = current.selectors(); fields["filter"] = filter; fields["follow"] = .bool(false)
            fields["stream_id"] = .string("stream_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
            if let cursor { fields["cursor"] = cursor }
            return fields
        }
        do {
            if journalCursor == nil {
                // Bootstrap from a bounded recent window: the head position, then the hooks shortly before it.
                let head = try await client.stream("session.journal.subscribe", params: params(nil), limit: 1).cursor
                guard let generation = head["generation"].string, let revision = head["revision"].string.flatMap(UInt64.init) else { throw stale() }
                hooks = TuiHookStates()
                journalCursor = .object(["generation": .string(generation), "revision": .string(String(revision > journalWindow ? revision - journalWindow : 0))])
            }
            for _ in 0..<4 {
                guard let cursor = journalCursor else { break }
                let page = try await client.stream("session.journal.subscribe", params: params(cursor), limit: 1_000)
                page.items.forEach { hooks.apply($0) }
                if page.cursor["revision"].string != nil { journalCursor = page.cursor }
                if page.complete { break }
            }
            return hooks.states
        } catch {
            journalCursor = nil; hooks = TuiHookStates()
            return [:]
        }
    }
    /// A phone send takes over the Agent input: a desktop draft is erased and a dialog is dismissed first.
    /// Text is only typed into a positively empty prompt, so a screen that stays unrecognized still rejects it.
    private func clearPromptForSend(_ start: TuiSessionSnapshot, binding: TuiSessionSnapshot.Binding, operationKey: String) async throws -> (TuiSessionSnapshot, TuiTerminalState) {
        var current = start, state = try await terminalState(start, binding: binding)
        for round in 0..<3 {
            if prompt.isEmpty(state, provider: binding.provider) { return (current, state) }
            var request = current.selectors(binding); request["expected_revision"] = .string(current.revision)
            let key = "cmux-remote:send-clear:" + operationKey.lowercased() + ":\(round)"
            if let typed = prompt.typedText(state, provider: binding.provider), !typed.isEmpty {
                // Placeholders such as pasted-text chips render longer or shorter than their input; spare erases are harmless.
                request["text"] = .string(String(repeating: "\u{7f}", count: min(typed.count + 16, 70_000)))
                try await effect("terminal.input.write", fields: request, key: key, generation: current.generation)
            } else {
                request["keys"] = .array([.string("escape")])
                try await effect("terminal.input.keys", fields: request, key: key, generation: current.generation)
            }
            try await Task.sleep(for: restoreInterval)
            current = try await snapshot()
            guard current.generation == start.generation, stillBound(binding, in: current) else { throw stale() }
            state = try await terminalState(current, binding: binding)
        }
        if prompt.isEmpty(state, provider: binding.provider) { return (current, state) }
        throw BridgeError("input_busy", "The Agent prompt could not be cleared for the phone.", status: 409)
    }
    /// Claude Code puts a prompt interrupted before its reply back into the input, which would block every later send.
    /// Only that exact text is erased; a desktop draft, a dialog or anything else stays untouched.
    private func clearRestoredPrompt(_ sent: String, binding: TuiSessionSnapshot.Binding, operationKey: String) async {
        let expected = sent.filter { !$0.isWhitespace }
        for check in 0..<restoreChecks {
            if check > 0 { try? await Task.sleep(for: restoreInterval) }
            guard !Task.isCancelled, let current = try? await snapshot(), stillBound(binding, in: current),
                  let state = try? await terminalState(current, binding: binding), let typed = prompt.typedText(state, provider: binding.provider) else { return }
            if typed.isEmpty { continue }
            guard typed.filter({ !$0.isWhitespace }) == expected else { return }
            var request = current.selectors(binding)
            request["text"] = .string(String(repeating: "\u{7f}", count: sent.count)); request["expected_revision"] = .string(current.revision)
            try? await effect("terminal.input.write", fields: request, key: "cmux-remote:interrupt-clear:" + operationKey.lowercased(), generation: current.generation)
            return
        }
    }
    private func effect(_ operation: String, fields: [String: JSONValue], key: String, generation: String) async throws {
        let result = try await client.resource(operation, params: fields, idempotencyKey: key)
        guard result["value"].object != nil, result["generation"].string == generation,
              let revision = result["revision"].string, UInt64(revision) != nil, result["replayed"].bool != nil else {
            throw BridgeError("outcome_unknown", "The daemon omitted a valid mutation receipt; inspect before repeating input.", status: 409)
        }
    }
    private func snapshot() async throws -> TuiSessionSnapshot {
        let current = try TuiSessionSnapshot(await client.resource("session.snapshot", params: ["machine": .string("current"), "session": .string("current")], idempotencyKey: nil))
        let identity = current.machine + ":" + current.session
        guard pinnedIdentity == nil || pinnedIdentity == identity else { throw BridgeError("stale_binding", "The selected daemon identity changed; reconnect explicitly.", status: 409) }
        pinnedIdentity = identity
        if !archiveLoaded {
            for binding in try archive?.load(identity: identity) ?? [] { catalog[binding.id] = binding }
            archiveLoaded = true
        }
        var next = catalog
        for binding in current.bindings { next[binding.id] = binding }
        guard next.count <= 200 else { throw BridgeError("too_large", "The daemon conversation archive is full.", status: 413) }
        if next != catalog { try archive?.save(identity: identity, rows: Array(next.values)) }
        catalog = next
        knownConversations.formUnion(catalog.keys)
        knownSurfaces.formUnion(current.surfaces)
        knownWorkspaces.formUnion(current.rawWorkspaces.keys)
        guard knownSurfaces.count <= 16_384, knownConversations.count <= 16_384, knownWorkspaces.count <= 16_384 else { throw BridgeError("too_large", "The daemon resource routing table is full.", status: 413) }
        return current
    }
    /// The owner's login shell from the account database, falling back to zsh; the daemon never expands `$SHELL`.
    static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let shell = String(cString: raw)
            if shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) { return shell }
        }
        return "/bin/zsh"
    }
    private func terminalState(_ current: TuiSessionSnapshot, binding: TuiSessionSnapshot.Binding) async throws -> TuiTerminalState {
        try TuiTerminalState(await client.resource("terminal.state.read", params: current.selectors(binding), idempotencyKey: nil))
    }
    private func descriptor(_ binding: TuiSessionSnapshot.Binding) -> [String: JSONValue] {
        ["session_id": .string(binding.id), "agent": .string(binding.provider), "title": .string(binding.title), "cwd": binding.cwd.map(JSONValue.string) ?? .null,
         "workspace_id": .string(binding.workspaceID), "surface_id": .string(binding.surfaceID), "state": .string(binding.state), "status": .string(binding.state)]
    }
    /// The live hook binding, or the archived one whose terminal is still running: an Agent that resumed without the
    /// daemon re-registering it keeps its terminal, so it stays reachable instead of reading as historical.
    /// A terminal that a live binding already claims is not revived, so a replacement session is never mistaken for
    /// the conversation that used to run there.
    private func activeBinding(id: String?, in current: TuiSessionSnapshot) -> TuiSessionSnapshot.Binding? {
        guard let id else { return nil }
        let key = id.lowercased()
        if let live = current.bindings.first(where: { $0.id.lowercased() == key }) { return live }
        guard let archived = catalog.values.first(where: { $0.id.lowercased() == key }), current.runningTerminals.contains(archived.surfaceID) else { return nil }
        return current.bindings.contains { $0.surfaceID == archived.surfaceID } ? nil : archived
    }
    /// The same rule keyed by the phone's surface id, for reads that name a surface rather than a conversation.
    private func activeBinding(surfaceID: String?, in current: TuiSessionSnapshot) -> TuiSessionSnapshot.Binding? {
        guard let id = surfaceID?.lowercased() else { return nil }
        if let live = current.bindings.first(where: { $0.surfaceID == id }) { return live }
        guard !current.bindings.contains(where: { $0.surfaceID == id }) else { return nil }
        return catalog.values.first { $0.surfaceID == id && current.runningTerminals.contains($0.surfaceID) }
    }
    /// Whether the terminal's own screen shows this Agent waiting at its prompt, rather than the shell that replaced it
    /// once the Agent exited. A prompt prefix is enough: an empty prompt, a draft and a dialog all keep it.
    private func showsAgentPrompt(_ current: TuiSessionSnapshot, binding: TuiSessionSnapshot.Binding) async -> Bool? {
        // The rendered grid, not the raw screen text, which still carries the escape sequences that place the prompt.
        guard let state = try? await terminalState(current, binding: binding) else { return nil }
        let prefix = binding.provider == "claude" ? "❯\u{00a0}" : "› "
        return state.rows.contains { line in
            var body = Substring(line.drop(while: { $0 == " " }))
            if body.hasPrefix("│") { body = body.dropFirst().drop(while: { $0 == " " }) }
            return body.hasPrefix(prefix)
        }
    }
    /// A conversation whose Agent has exited but whose session can still be reopened: no live binding claims it, its
    /// workspace outlived the terminal, its own transcript names the directory to reopen it in, and — when the terminal
    /// is still running — that terminal is not showing the Agent's own prompt. Nothing here is trusted from the phone.
    private func resumableBinding(id: String?, in current: TuiSessionSnapshot, promptKnown: Bool? = nil) async -> (binding: TuiSessionSnapshot.Binding, cwd: String)? {
        guard let id, let binding = catalog.values.first(where: { $0.id.lowercased() == id.lowercased() }),
              !current.bindings.contains(where: { $0.id == binding.id }),
              current.rawWorkspaces[binding.workspaceID] != nil else { return nil }
        // A terminal that is gone is resumed from the transcript alone; a running one must not still hold the Agent.
        if current.runningTerminals.contains(binding.surfaceID) {
            let prompt: Bool?
            if let promptKnown { prompt = promptKnown } else { prompt = await showsAgentPrompt(current, binding: binding) }
            // Only a positively identified shell prompt makes a running terminal resumable: an unreadable screen could
            // still hold the Agent, and reopening it would run two processes on one session.
            guard prompt == false else { return nil }
        }
        guard let recorded = try? transcripts.recordedCwd(provider: binding.provider, sessionID: binding.providerSession),
              !recorded.isEmpty else { return nil }
        return (binding, recorded)
    }
    /// Whether the conversation is still the same live one across a re-read; a revived binding must pass this too.
    private func stillBound(_ binding: TuiSessionSnapshot.Binding, in current: TuiSessionSnapshot) -> Bool {
        activeBinding(id: binding.id, in: current) == binding
    }
    private func stale() -> BridgeError { BridgeError("stale_binding", "This daemon Agent no longer has its verified terminal/workspace binding.", status: 409) }
    private func unsupported() -> BridgeError { BridgeError("unsupported", "This operation is not supported by the daemon backend.", status: 422) }
}
