import Foundation
import CmuxRemoteCore
import CmuxAgentChat

/// Conversations proved by a Rex block's foreground Claude process. A terminal
/// with no such proof stays a terminal; this source never guesses.
public actor RexConversationSource {
    public struct Entry: Sendable {
        public var descriptor: SessionDescriptor
        public let transcript: String
    }

    private let provider: RexProvider
    private let registry: ClaudeProcessRegistry
    private let reader: TranscriptReader
    private let roots: [URL]
    private let hookSpool: RexHookSpool?
    /// Whether shell-only Rex blocks join the session list. Off until the phone
    /// has a way to present a terminal without a conversation.
    private let showsUnboundTerminals: Bool
    private let modelCatalog: ModelChoiceCatalog
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var terminalByConversation: [String: String] = [:]
    private let maximumEntries = 200

    public init(provider: RexProvider, home: URL, transcriptRoots: [URL], reader: TranscriptReader,
                hookSpool: RexHookSpool? = nil, showsUnboundTerminals: Bool = false) {
        self.provider = provider
        self.registry = ClaudeProcessRegistry(home: home)
        self.reader = reader
        self.roots = transcriptRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        self.hookSpool = hookSpool
        self.modelCatalog = ModelChoiceCatalog(home: home)
        self.showsUnboundTerminals = showsUnboundTerminals
    }

    public func conversations() async throws -> [Entry] {
        let targets = try await provider.conversationTargets(registry: registry, roots: roots)
        var fresh = Set<String>()
        var result: [Entry] = []
        for target in targets {
            let updated = (try? FileManager.default.attributesOfItem(atPath: target.transcript))?[.modificationDate] as? Date
            let descriptor = SessionDescriptor(id: target.agentSessionID, agent: "claude", title: target.title,
                                               cwd: target.cwd, workspaceID: target.space.id,
                                               surfaceID: target.terminal.id, state: target.state,
                                               updatedAt: updated, resumable: false, kind: "agent", source: "rex")
            let entry = Entry(descriptor: descriptor, transcript: target.transcript)
            entries[descriptor.id] = entry
            fresh.insert(descriptor.id)
            terminalByConversation[descriptor.id] = target.terminal.id
            result.append(entry)
            if !order.contains(descriptor.id) { order.append(descriptor.id) }
        }
        let localHost = await provider.localHost
        if let hookSpool, localHost {
            // Hooks are the source for Codex and a second proof for Claude. A
            // record is accepted only while its block's foreground is that
            // Agent, so a stale file cannot revive a shell.
            for record in hookSpool.records().sorted(by: { $0.recordedAt > $1.recordedAt }) {
                guard !fresh.contains(record.sessionID), transcriptAllowed(record.transcript) else { continue }
                guard FileManager.default.fileExists(atPath: record.transcript),
                      let terminal = await provider.terminal(forBlock: record.rexBlock),
                      terminal.state != "exited", terminal.processName == record.agent else { continue }
                let pane = terminal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                var resolved: String? = (pane.isEmpty || ["shell", "terminal"].contains(pane.lowercased())) ? nil : pane
                if resolved == nil { resolved = await provider.terminalTitle(terminalID: terminal.id) }
                if resolved == nil { resolved = URL(fileURLWithPath: record.cwd).lastPathComponent }
                let name = resolved ?? record.sessionID
                let state: String
                switch record.event {
                case "SessionEnd": state = "ended"
                case "Stop": state = "idle"
                default: state = "working"
                }
                let descriptor = SessionDescriptor(id: record.sessionID, agent: record.agent,
                                                   title: name.isEmpty ? record.sessionID : name,
                                                   cwd: record.cwd, workspaceID: terminal.spaceID,
                                                   surfaceID: terminal.id, state: state,
                                                   updatedAt: record.recordedAt, resumable: false,
                                                   kind: "agent", source: "rex")
                let entry = Entry(descriptor: descriptor, transcript: record.transcript)
                entries[descriptor.id] = entry
                fresh.insert(descriptor.id)
                terminalByConversation[descriptor.id] = terminal.id
                result.append(entry)
                if !order.contains(descriptor.id) { order.append(descriptor.id) }
                if result.count >= 128 { break }
            }
        }
        for id in order where !fresh.contains(id) {
            guard var entry = entries[id], FileManager.default.fileExists(atPath: entry.transcript) else { continue }
            entry.descriptor.state = "ended"
            entry.descriptor.resumable = entry.descriptor.cwd != nil && entry.descriptor.workspaceID != nil
            entries[id] = entry
            result.append(entry)
        }
        if order.count > maximumEntries {
            let dropped = order.prefix(order.count - maximumEntries)
            for id in dropped { entries[id] = nil }
            order.removeFirst(dropped.count)
        }
        return result
    }

    /// Proved conversations plus every other Rex terminal block. A terminal
    /// row is listed only for clients that asked for terminalView.
    public func rows() async throws -> [Entry] {
        var result = try await conversations()
        guard showsUnboundTerminals else { return result }
        let targets = try await provider.conversationTargets(registry: registry, roots: roots)
        var bound = Set(targets.map(\.terminal.id))
        let spaces = try await provider.spaces()
        for space in spaces {
            guard let terminals = try? await provider.terminals(spaceID: space.id) else { continue }
            for terminal in terminals where !bound.contains(terminal.id) {
                bound.insert(terminal.id)
                let id = "rex-terminal:" + terminal.id
                let descriptor = SessionDescriptor(id: id, agent: "terminal", title: terminal.title,
                                                   cwd: terminal.workingDirectory, workspaceID: space.id,
                                                   surfaceID: terminal.id,
                                                   state: terminal.state == "running" ? "idle" : "ended",
                                                   resumable: false, kind: "terminal", source: "rex")
                let entry = Entry(descriptor: descriptor, transcript: "")
                entries[id] = entry
                if !order.contains(id) { order.append(id) }
                result.append(entry)
                if result.count >= 256 { return result }
            }
        }
        return result
    }

    public func entry(_ id: String) async throws -> Entry {
        _ = try await rows()
        guard let entry = entries[id] else { throw BridgeError("session_not_found", "This Rex conversation is no longer available.", status: 404) }
        return entry
    }

    public func history(_ id: String, beforeSeq: Int?, limit: Int) async throws -> ConversationSnapshot {
        let entry = try await entry(id)
        if entry.descriptor.kind == "terminal" {
            return ConversationSnapshot(messages: [], hasMore: false,
                                        generation: "terminal:" + (entry.descriptor.surfaceID ?? id), clipped: false)
        }
        return try await reader.history(path: entry.transcript, agent: "claude", beforeSeq: beforeSeq, limit: limit,
                                        allowsUncreatedTranscript: false, reportsBackgroundTasks: false)
    }

    public func archive(_ id: String, tail: Int?, cursor: String?, limit: Int) async throws -> ConversationArchivePage {
        let entry = try await entry(id)
        guard entry.descriptor.kind != "terminal" else { throw BridgeError("unsupported", "A Rex terminal has no conversation archive.", status: 422) }
        return try await reader.archive(path: entry.transcript, agent: "claude", tail: tail, cursor: cursor, limit: limit,
                                        reportsBackgroundTasks: false)
    }

    public func toolText(_ id: String, messageID: String, generation: String, field: String,
                         offset: Int, contentID: String?, limit: Int) async throws -> ToolTextPage {
        let entry = try await entry(id)
        guard entry.descriptor.kind != "terminal" else { throw BridgeError("unsupported", "A Rex terminal has no tool record.", status: 422) }
        return try await reader.toolText(path: entry.transcript, agent: "claude", messageID: messageID,
                                         generation: generation, field: field, offset: offset, contentID: contentID, limit: limit)
    }

    public func image(_ id: String, referenceID: String, generation: String) async throws -> Data {
        let entry = try await entry(id)
        guard entry.descriptor.kind != "terminal" else { throw BridgeError("unsupported", "A Rex terminal has no recorded image.", status: 422) }
        let image = try await reader.image(path: entry.transcript, agent: "claude",
                                           referenceID: referenceID, generation: generation)
        switch image.source {
        case .recorded(let data): return try HistoricalImageProjection().preview(data)
        case .projectPath: throw BridgeError("image_unavailable", "This Rex image is not recorded in its transcript.", status: 404)
        }
    }

    public func preview(_ id: String) async throws -> PreviewSnapshot {
        let entry = try await entry(id)
        guard entry.descriptor.state != "ended", let terminal = entry.descriptor.surfaceID else {
            return PreviewSnapshot(text: nil, available: false)
        }
        let snapshot = try await provider.snapshot(terminalID: terminal)
        let rows = snapshot.text.components(separatedBy: .newlines)
        if entry.descriptor.kind == "terminal" {
            return PreviewSnapshot(text: snapshot.text, available: true)
        }
        let text = AgentChatProseScreenExtractor().extract(lines: rows, agentKind: ChatAgentKind(source: entry.descriptor.agent))
        return PreviewSnapshot(text: text, available: true, compacting: TuiCompactionScreen.isCompacting(rows: rows))
    }

    public func sendText(_ id: String, text: String,
                         authorize: @Sendable () async throws -> Void) async throws {
        let described = try await entry(id).descriptor
        guard described.kind != "terminal" else {
            throw BridgeError("unsupported", "Use the terminal input route for a Rex terminal.", status: 422)
        }
        let terminal = try await requireLive(id)
        let providerName = entries[id]?.descriptor.agent ?? "claude"
        let snapshot = try await provider.snapshot(terminalID: terminal)
        guard TuiPromptSafety().isEmpty(snapshot.text, provider: providerName) else {
            throw BridgeError("input_busy", "The Rex agent has a draft or an open question. Resolve it first.", status: 409)
        }
        try await authorize()
        try await provider.write(terminalID: terminal, data: text + "\r")
    }

    public func interrupt(_ id: String, hard: Bool,
                          authorize: @Sendable () async throws -> Void) async throws {
        let described = try await entry(id).descriptor
        guard described.kind != "terminal" else {
            throw BridgeError("unsupported", "Use the terminal input route for a Rex terminal.", status: 422)
        }
        let terminal = try await requireLive(id)
        try await authorize()
        try await provider.write(terminalID: terminal, data: hard ? "\u{3}" : "\u{1b}")
    }

    public func models(_ id: String) async throws -> ModelChoiceList {
        let described = try await entry(id).descriptor
        guard described.kind != "terminal" else {
            throw BridgeError("unsupported", "A Rex terminal has no model list.", status: 422)
        }
        // Codex's picker is screen-driven; do not offer a menu this adapter
        // cannot switch reliably. Switching a Rex Codex session waits for a
        // verified picker adapter.
        guard described.agent == "claude" else {
            return ModelChoiceList(choices: [], acceptsCustom: false, persistsDefault: false)
        }
        return modelCatalog.choices(agent: described.agent)
    }

    public func switchModel(_ id: String, model: String, confirm: Bool,
                            authorize: @Sendable () async throws -> Void) async throws {
        let described = try await entry(id).descriptor
        guard described.kind != "terminal" else {
            throw BridgeError("unsupported", "A Rex terminal has no model switch.", status: 422)
        }
        guard described.agent == "claude" else {
            throw BridgeError("unsupported", "Rex drives Claude model switching; Codex uses its picker.", status: 422)
        }
        let name = try AgentModelName.validated(model)
        let terminal = try await requireLive(id)
        let before = try await provider.snapshot(terminalID: terminal)
        guard TuiPromptSafety().isEmpty(before.text, provider: "claude") else {
            throw BridgeError("agent_busy", "The Rex agent is not waiting at its prompt.", status: 409)
        }
        try await authorize()
        try await provider.write(terminalID: terminal, data: "/model " + name + "\r")
        // Claude may ask to re-read a long conversation before switching. Only the
        // question is answered here; anything else stays outcome-unknown to the caller.
        for _ in 0..<6 {
            let screen = try await provider.snapshot(terminalID: terminal).text.lowercased()
            if screen.contains("switch model") || screen.contains("switch to") {
                if confirm { try await provider.write(terminalID: terminal, data: "\r") }
                else { try await provider.write(terminalID: terminal, data: "\u{1b}"); throw BridgeError("model_confirm_required", "The agent asked to confirm the model switch.", status: 409) }
                return
            }
            if !screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !screen.contains("model") { return }
        }
    }

    public func resume(_ id: String, authorize: @Sendable () async throws -> Void) async throws -> TerminalDescriptor {
        let entry = try await entry(id)
        guard entry.descriptor.kind != "terminal" else {
            throw BridgeError("unsupported", "A Rex terminal has no conversation to resume.", status: 422)
        }
        guard let space = entry.descriptor.workspaceID, let cwd = entry.descriptor.cwd else {
            throw BridgeError("read_only", "This conversation cannot be reopened.", status: 409)
        }
        let command = entry.descriptor.agent == "codex"
            ? ["codex", "resume", entry.descriptor.id]
            : ["claude", "--resume", entry.descriptor.id]
        try await authorize()
        return try await provider.start(spaceID: space, command: command, cwd: cwd)
    }

    public func rename(_ id: String, title: String, authorize: @Sendable () async throws -> Void) async throws {
        guard title.utf8.count <= 512 else { throw BridgeError("invalid_input", "The title is too long.", status: 400) }
        let entry = try await entry(id)
        guard entry.descriptor.kind != "terminal" else {
            throw BridgeError("unsupported", "A Rex terminal is renamed with its block label on the host.", status: 422)
        }
        guard entry.descriptor.state != "ended", let terminal = entry.descriptor.surfaceID else {
            throw BridgeError("read_only", "This conversation has no live Rex terminal.", status: 409)
        }
        try await authorize()
        try await provider.setLabel(terminalID: terminal, label: title)
    }

    private func requireLive(_ id: String) async throws -> String {
        _ = try await rows()
        guard let entry = entries[id], entry.descriptor.state != "ended",
              let terminalID = terminalByConversation[id] else {
            throw BridgeError("read_only", "This Rex conversation has no live verified terminal.", status: 409)
        }
        guard let terminal = try? await provider.terminal(terminalID),
              terminal.state != "exited", terminal.processName == entry.descriptor.agent else {
            throw BridgeError("read_only", "The Agent has left this Rex terminal.", status: 409)
        }
        return terminalID
    }

    private func transcriptAllowed(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension == "jsonl" else { return false }
        return roots.contains { url.path.hasPrefix($0.path + "/") }
    }
}
