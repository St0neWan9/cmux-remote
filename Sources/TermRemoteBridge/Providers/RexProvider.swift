import Foundation
import CryptoKit
import TermRemoteCore

/// A Rex server as a term remote provider. Rex sessions become spaces, Rex
/// terminal blocks become terminals, and a Rex window is only layout.
public actor RexProvider: TerminalProvider {
    public struct ConversationTarget: Sendable, Equatable {
        public let space: SpaceDescriptor
        public let terminal: TerminalDescriptor
        public let agentSessionID: String
        public let transcript: String
        /// The directory the Agent recorded in its own registry, not a moved
        /// terminal cwd or a symlink spelling.
        public let cwd: String
        public let title: String
        public let state: String
    }

    private struct TerminalRef: Sendable {
        let space: String
        let session: String
        let block: String
    }

    private let endpoint: RexEndpoint
    private let client: RexControlClient
    private let mutations: MutationLedger
    private let label: String
    private var identity: ProviderDescriptor
    private var nativeSessions: [String: String] = [:]
    private var terminalRefs: [String: TerminalRef] = [:]
    private var isLocalHost: Bool {
        switch endpoint {
        case .unix: return true
        case .tcp(let host, _, _): return ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
        }
    }

    public init(endpoint: RexEndpoint, label: String, mutations: MutationLedger) {
        self.endpoint = endpoint
        self.label = label
        self.mutations = mutations
        self.client = RexControlClient(endpoint: endpoint)
        self.identity = ProviderDescriptor(
            id: ProviderIdentity.providerID(kind: .rex, instance: endpoint.display),
            kind: .rex, name: label, hostName: label,
            capabilities: [.spaces, .layout, .terminals, .screen, .input], status: .starting)
    }

    public var descriptor: ProviderDescriptor { identity }
    /// Whether this provider runs on the same machine as the Bridge. Only then
    /// may local Claude registries and hook spools be used as proof.
    public var localHost: Bool { isLocalHost }

    public func close() async { await client.close() }

    public func spaces() async throws -> [SpaceDescriptor] {
        do {
            let status = try await describeServer()
            let value = try await client.request("session.list")
            let rows = value["sessions"].array ?? []
            guard rows.count <= 256 else { throw BridgeError("rex_invalid", "Rex returned too many sessions.", status: 502) }
            var sessions: [String: String] = [:]
            var spaces: [SpaceDescriptor] = []
            for row in rows {
                guard let native = row["session_id"].string, native.hasPrefix("session:") else { continue }
                let id = ProviderIdentity.resourceID(providerID: identity.id, kind: "space", nativeID: native)
                sessions[id] = native
                let title = row["label"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
                spaces.append(SpaceDescriptor(id: id, providerID: identity.id,
                                              title: title.flatMap { $0.isEmpty ? nil : $0 } ?? native,
                                              kind: "session"))
            }
            nativeSessions = sessions
            markAvailable(status)
            return spaces
        } catch {
            markUnavailable(error)
            throw error
        }
    }

    public func terminals(spaceID: String) async throws -> [TerminalDescriptor] {
        let session = try await nativeSession(for: spaceID)
        do {
            // Block methods such as `process` need this connection attached to the session, not only
            // attached to the whole server. Attaching is idempotent and also covers a reconnect.
            _ = try? await client.request("session.attach", ["session_id": .string(session)])
            let view = try await client.request("session.view", ["session_id": .string(session)])
            let windows = view["windows"].array ?? []
            guard windows.count <= 64 else { throw BridgeError("rex_invalid", "Rex returned too many windows.", status: 502) }
            var descriptors: [TerminalDescriptor] = []
            var refs: [String: TerminalRef] = [:]
            var pendingProcesses: [(String, String)] = []
            for window in windows {
                guard let windowID = window["window_id"].string else { continue }
                let layoutID = ProviderIdentity.resourceID(providerID: identity.id, kind: "layout", nativeID: windowID)
                for layer in window["layers"].array ?? [] {
                    for block in layer["blocks"].array ?? [] {
                        guard block["creator_name"].string == "com.superlogical.terminal",
                              let native = block["block_id"].string else { continue }
                        let id = ProviderIdentity.resourceID(providerID: identity.id, kind: "terminal", nativeID: native)
                        let name = block["label"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = name.flatMap { $0.isEmpty ? nil : $0 }
                            ?? window["label"].string
                            ?? "Terminal"
                        refs[id] = TerminalRef(space: spaceID, session: session, block: native)
                        descriptors.append(TerminalDescriptor(id: id, providerID: identity.id, spaceID: spaceID,
                                                              title: title, kind: "terminal", state: "unknown",
                                                              layoutID: layoutID))
                        if pendingProcesses.count < 16 { pendingProcesses.append((id, native)) }
                    }
                }
            }
            for (id, native) in pendingProcesses {
                guard let info = try? await client.request("com.superlogical.terminal.process", [
                    "session_id": .string(session), "block_id": .string(native), "args": .object([:])
                ]) else { continue }
                let foreground = info["foreground"]
                // argv0 is how a program names itself; Rex's `name` is the
                // executable's file name, which differs for wrappers.
                let processName = foreground["argv0"].string ?? foreground["name"].string
                let cwd = foreground["cwd"].string
                let pid = foreground["pid"].int
                let state = info["last_exit"].object == nil ? "running" : "exited"
                if let index = descriptors.firstIndex(where: { $0.id == id }) {
                    let old = descriptors[index]
                    descriptors[index] = TerminalDescriptor(id: old.id, providerID: old.providerID, spaceID: old.spaceID,
                                                            title: old.title, kind: old.kind, processName: processName,
                                                            workingDirectory: cwd, state: state, layoutID: old.layoutID,
                                                            processID: pid)
                }
            }
            for key in terminalRefs.keys where terminalRefs[key]?.space == spaceID { terminalRefs.removeValue(forKey: key) }
            terminalRefs.merge(refs) { _, new in new }
            guard terminalRefs.count <= 256 else { throw BridgeError("rex_invalid", "Rex returned too many terminals.", status: 502) }
            markAvailable(nil)
            return descriptors
        } catch {
            markUnavailable(error)
            throw error
        }
    }

    public func layout(spaceID: String) async throws -> LayoutSnapshot {
        let session = try await nativeSession(for: spaceID)
        do {
            let view = try await client.request("session.view", ["session_id": .string(session)])
            var nodes: [LayoutNode] = []
            for window in view["windows"].array ?? [] {
                guard let windowID = window["window_id"].string else { continue }
                let nodeID = ProviderIdentity.resourceID(providerID: identity.id, kind: "layout", nativeID: windowID)
                nodes.append(LayoutNode(id: nodeID, kind: "window", title: window["label"].string))
                for layer in window["layers"].array ?? [] {
                    for block in layer["blocks"].array ?? [] {
                        guard block["creator_name"].string == "com.superlogical.terminal",
                              let blockID = block["block_id"].string else { continue }
                        let terminalID = ProviderIdentity.resourceID(providerID: identity.id, kind: "terminal", nativeID: blockID)
                        nodes.append(LayoutNode(id: terminalID, kind: "terminal", terminalID: terminalID,
                                                parentID: nodeID, title: block["label"].string))
                    }
                }
            }
            let signature = nodes.map { [$0.id, $0.kind, $0.terminalID ?? "", $0.parentID ?? ""].joined(separator: "\u{0}") }.joined(separator: "\u{1}")
            markAvailable(nil)
            return LayoutSnapshot(providerID: identity.id, spaceID: spaceID, revision: Self.digest(signature), nodes: nodes)
        } catch {
            markUnavailable(error)
            throw error
        }
    }

    public func terminal(_ id: String) async throws -> TerminalDescriptor {
        if let ref = terminalRefs[id.lowercased()] {
            let items = try await terminals(spaceID: ref.space)
            if let match = items.first(where: { $0.id == id.lowercased() }) { return match }
        }
        for space in try await spaces() {
            guard let items = try? await terminals(spaceID: space.id) else { continue }
            if let match = items.first(where: { $0.id == id.lowercased() }) { return match }
        }
        throw BridgeError("terminal_not_found", "Unknown Rex terminal.", status: 404)
    }

    /// The visible screen with its styles, or nil when Rex cannot return it in one bounded reply.
    ///
    /// Claude shows a suggested next prompt as faint text in an empty input box. Plain text loses
    /// the faintness, so the suggestion reads as a draft; the `vt` format keeps it.
    func styledScreen(terminalID: String) async throws -> TuiTerminalState? {
        let ref = try await reference(terminalID)
        let result = try await client.request("com.superlogical.terminal.format", [
            "session_id": .string(ref.session), "block_id": .string(ref.block),
            "args": .object(["format": .string("vt"), "max_bytes": .number(983_040)])
        ])
        // A partial reply would leave the screen half drawn; the caller falls back to plain text.
        guard result["id"].int == nil, let content = result["content"].string else { return nil }
        let size = try await client.request("com.superlogical.terminal.size", [
            "session_id": .string(ref.session), "block_id": .string(ref.block), "args": .object([:])
        ])
        guard let columns = size["columns"].int, let rows = size["rows"].int else { return nil }
        return try TuiTerminalState(columns: columns, rows: rows, vt: Data(content.utf8))
    }

    public func snapshot(terminalID: String) async throws -> TerminalSnapshot {
        let ref = try await reference(terminalID)
        do {
            let result = try await client.request("com.superlogical.terminal.format", [
                "session_id": .string(ref.session), "block_id": .string(ref.block),
                // Keep trailing spaces: Claude's prompt prefix is a no-break
                // space and Codex's is a regular space, and trimming erases
                // the exact row that proves the input line is empty.
                "args": .object(["format": .string("text"), "trim": .bool(false), "unwrap": .bool(true),
                                 "max_bytes": .number(262_144)])
            ])
            var content = result["content"].string ?? ""
            var cursor = result["id"].int
            var offset = content.utf8.count
            var truncated = result["id"].int != nil
            while let id = cursor, content.utf8.count < ProviderDirectory.maximumScreenBytes {
                let page = try await client.request("com.superlogical.terminal.blob_read", [
                    "session_id": .string(ref.session), "block_id": .string(ref.block),
                    "args": .object(["id": .number(Double(id)), "offset": .number(Double(offset)), "max_bytes": .number(49_152)])
                ])
                guard let data = page["data"].string else { break }
                content += data
                offset += data.utf8.count
                cursor = page["eof"].bool == true ? nil : page["id"].int
                truncated = cursor != nil || content.utf8.count >= ProviderDirectory.maximumScreenBytes
            }
            let size = try? await client.request("com.superlogical.terminal.size", [
                "session_id": .string(ref.session), "block_id": .string(ref.block), "args": .object([:])
            ])
            markAvailable(nil)
            return TerminalSnapshot(providerID: identity.id, spaceID: ref.space, terminalID: terminalID,
                                    revision: Self.digest(content), columns: size.flatMap { $0["columns"].int } ?? 0,
                                    rows: size.flatMap { $0["rows"].int } ?? 0, format: "text", text: content,
                                    truncated: truncated)
        } catch {
            markUnavailable(error)
            throw error
        }
    }

    public func send(_ input: TerminalInputRequest, clientID: String, terminalID: String,
                     authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt {
        let ref = try await reference(terminalID)
        let text = input.submit == true ? input.text + "\r" : input.text
        guard !text.isEmpty, text.utf8.count <= ProviderDirectory.maximumInputBytes else {
            throw BridgeError("invalid_input", "Terminal input must be non-empty and bounded.", status: 400)
        }
        let payload: JSONValue = .object(["text": .string(text), "submit": .bool(input.submit == true)])
        let fingerprint = try MutationLedger.fingerprint(action: "rex.terminal.input",
                                                         resource: identity.id + ":" + terminalID.lowercased(),
                                                         payload: payload)
        if let prior = try await mutations.prior(clientID: clientID, operationID: input.operationID, fingerprint: fingerprint) {
            try await authorize()
            guard let receipt = prior.receipt else {
                throw BridgeError("outcome_unknown", "The previous terminal input outcome is unknown.", status: 409)
            }
            return receipt
        }
        if try await mutations.begin(clientID: clientID, operationID: input.operationID, fingerprint: fingerprint,
                                     workspaceID: ref.space, capability: .terminalInput) != nil {
            throw BridgeError("outcome_unknown", "The previous terminal input outcome is unknown.", status: 409)
        }
        do {
            try await authorize()
            let result = try await client.request("com.superlogical.terminal.write", [
                "session_id": .string(ref.session), "block_id": .string(ref.block),
                "args": .object(["data": .string(text)])
            ])
            guard result["bytes_written"].int != nil else {
                throw BridgeError("outcome_unknown", "The terminal input outcome is unknown.", status: 409)
            }
            markAvailable(nil)
            return try await mutations.complete(clientID: clientID, operationID: input.operationID)
        } catch {
            markUnavailable(error)
            throw BridgeError("outcome_unknown", "The terminal input outcome is unknown; it was not retried.", status: 409)
        }
    }

    /// Claude conversations whose block foreground is the Agent process and
    /// whose own registry proves the session id and transcript. A Codex block
    /// stays a terminal until a supported binding exists.
    public func conversationTargets(registry: ClaudeProcessRegistry, roots: [URL]) async throws -> [ConversationTarget] {
        // A pid on another machine has nothing to do with this Mac's Claude
        // registry. Remote Agent binding needs a remote transcript source.
        guard isLocalHost else { return [] }
        var result: [ConversationTarget] = []
        for space in try await spaces() {
            guard let items = try? await terminals(spaceID: space.id) else { continue }
            for terminal in items {
                guard terminal.processName == "claude", let pid = terminal.processID,
                      let binding = registry.binding(pid: pid, cwd: terminal.workingDirectory, roots: roots) else { continue }
                let tab = terminal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                var resolved: String? = (tab.isEmpty || ["shell", "terminal"].contains(tab.lowercased())) ? nil : tab
                if resolved == nil { resolved = await self.title(for: terminal.id) }
                if resolved == nil { resolved = URL(fileURLWithPath: binding.cwd).lastPathComponent }
                let name = resolved ?? binding.sessionID
                result.append(ConversationTarget(space: space, terminal: terminal,
                                                 agentSessionID: binding.sessionID, transcript: binding.transcript,
                                                 cwd: binding.cwd,
                                                 title: name.isEmpty ? binding.sessionID : name,
                                                 state: binding.status == "idle" ? "idle" : "working"))
                if result.count >= 128 { return result }
            }
        }
        return result
    }

    /// Types into a block for a caller that owns the durable operation. The
    /// conversation path uses this so one mutation has exactly one journal.
    public func write(terminalID: String, data: String) async throws {
        guard !data.isEmpty, data.utf8.count <= ProviderDirectory.maximumInputBytes else {
            throw BridgeError("invalid_input", "Terminal input must be non-empty and bounded.", status: 400)
        }
        let ref = try await reference(terminalID)
        let result = try await client.request("com.superlogical.terminal.write", [
            "session_id": .string(ref.session), "block_id": .string(ref.block),
            "args": .object(["data": .string(data)])
        ])
        guard result["bytes_written"].int != nil else {
            throw BridgeError("outcome_unknown", "The terminal input outcome is unknown.", status: 409)
        }
        markAvailable(nil)
    }

    /// The terminal behind a native Rex block id, for a hook record that names
    /// the block rather than a derived UUID.
    public func terminal(forBlock blockID: String) async -> TerminalDescriptor? {
        for space in (try? await spaces()) ?? [] {
            guard let items = try? await terminals(spaceID: space.id) else { continue }
            if let match = items.first(where: { terminalRefs[$0.id]?.block == blockID }) { return match }
        }
        return nil
    }

    public func terminalTitle(terminalID: String) async -> String? { await title(for: terminalID) }

    public func setLabel(terminalID: String, label: String) async throws {
        guard label.utf8.count <= 512, !label.contains("\u{0}") else {
            throw BridgeError("invalid_input", "Invalid terminal label.", status: 400)
        }
        let ref = try await reference(terminalID)
        _ = try await client.request("session.set_block_label", [
            "session_id": .string(ref.session), "block_id": .string(ref.block), "label": .string(label)
        ])
        _ = try? await terminals(spaceID: ref.space)
    }

    /// Starts a fixed command in a new block of an existing Rex session. The
    /// caller supplies an argv, never a shell string.
    public func start(spaceID: String, command: [String], cwd: String?) async throws -> TerminalDescriptor {
        guard !command.isEmpty, command.count <= 16, command.allSatisfy({ !$0.contains("\u{0}") && $0.utf8.count <= 4_096 }) else {
            throw BridgeError("invalid_input", "Invalid start command.", status: 400)
        }
        let session = try await nativeSession(for: spaceID)
        let options: [String: JSONValue] = [
            "command": .array(command.map { .string($0) }),
            "cwd": .string(cwd ?? ""),
            "interactive": .bool(true)
        ]
        let layout: JSONValue = .object(["block": .object([
            "flavor": .string("com.superlogical.terminal.shell"),
            "options": .object(options)
        ])])
        let split: [String: JSONValue] = [
            "session_id": .string(session), "direction": .string("horizontal"), "side": .string("after"),
            "layout": layout, "focus": .bool(false)
        ]
        var blockID: String?
        do {
            let result = try await client.request("session.new_split", split)
            blockID = result["block_ids"].array?.first?.string
        } catch let failure as BridgeError where failure.code == "conflict" || failure.code == "not_found" {
            let window: [String: JSONValue] = ["session_id": .string(session), "layout": layout, "focus": .bool(false)]
            let result = try await client.request("session.new_window", window)
            blockID = result["block_ids"].array?.first?.string
                ?? result["initial_windows"].array?.first?["block_ids"].array?.first?.string
        }
        guard let blockID, let space = try await spaces().first(where: { $0.id == spaceID }) else {
            throw BridgeError("outcome_unknown", "Rex did not confirm the new terminal.", status: 409)
        }
        let terminalID = ProviderIdentity.resourceID(providerID: identity.id, kind: "terminal", nativeID: blockID)
        terminalRefs[terminalID] = TerminalRef(space: spaceID, session: session, block: blockID)
        if let items = try? await terminals(spaceID: space.id), let created = items.first(where: { $0.id == terminalID }) {
            return created
        }
        return TerminalDescriptor(id: terminalID, providerID: identity.id, spaceID: spaceID, title: "Terminal",
                                  kind: "terminal", state: "unknown")
    }

    private func title(for terminalID: String) async -> String? {
        guard let ref = try? await reference(terminalID),
              let result = try? await client.request("com.superlogical.terminal.title", [
                "session_id": .string(ref.session), "block_id": .string(ref.block), "args": .object([:])
              ]) else { return nil }
        let value = result["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func describeServer() async throws -> JSONValue {
        let status = try await client.request("server.status")
        let hostID = status["host_id"].string
        let revision = status["api_revision"].int
        updateIdentity(hostID: hostID, revision: revision, status: .available, errorCode: nil)
        return status
    }

    private func nativeSession(for spaceID: String) async throws -> String {
        if let native = nativeSessions[spaceID.lowercased()] ?? nativeSessions[spaceID] { return native }
        _ = try await spaces()
        if let native = nativeSessions[spaceID] ?? nativeSessions[spaceID.lowercased()] { return native }
        throw BridgeError("space_not_found", "Unknown Rex session.", status: 404)
    }

    private func reference(_ terminalID: String) async throws -> TerminalRef {
        let key = terminalID.lowercased()
        if let ref = terminalRefs[key] { return ref }
        _ = try await terminal(key)
        guard let ref = terminalRefs[key] else { throw BridgeError("terminal_not_found", "Unknown Rex terminal.", status: 404) }
        return ref
    }

    private func markAvailable(_ status: JSONValue?) {
        updateIdentity(hostID: status?["host_id"].string ?? identity.hostID,
                       revision: status?["api_revision"].int ?? identity.apiRevision.flatMap { Int($0) },
                       status: .available, errorCode: nil)
    }

    private func markUnavailable(_ error: any Error) {
        let code = (error as? BridgeError)?.code ?? "rex_unavailable"
        updateIdentity(hostID: identity.hostID, revision: identity.apiRevision.flatMap { Int($0) },
                       status: .unavailable, errorCode: code)
    }

    private func updateIdentity(hostID: String?, revision: Int?, status: ProviderStatus, errorCode: String?) {
        identity = ProviderDescriptor(id: identity.id, kind: .rex, name: label,
                                      hostID: hostID, hostName: identity.hostName,
                                      apiRevision: revision.map(String.init) ?? identity.apiRevision,
                                      capabilities: identity.capabilities, status: status, errorCode: errorCode)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
