import Foundation
import CryptoKit
import CmuxRemoteCore

/// Opens a new terminal running a fixed agent command inside one approved desktop workspace.
/// Folders come only from the workspace itself; a client picks a root by its opaque ID, never by host path.
public actor SessionLauncher {
    private let cmux: any CmuxControlling
    private let files: ProjectFilePolicy
    private let home: URL
    private let mutations: MutationLedger
    private let sessions: @Sendable () async throws -> [SessionDescriptor]
    static let rootLimit = 32
    static let listingLimit = 500

    public init(cmux: any CmuxControlling, home: URL, mutations: MutationLedger, sessions: @escaping @Sendable () async throws -> [SessionDescriptor]) {
        self.cmux = cmux; self.home = home.resolvingSymlinksInPath().standardizedFileURL
        files = ProjectFilePolicy(home: home); self.mutations = mutations; self.sessions = sessions
    }

    public func directories(workspaceID: String, access: SessionAccess) async throws -> [LaunchDirectory] {
        try await access.require(.conversationStart, workspace: workspaceID)
        let found = try await roots(workspaceID: workspaceID)
        try await access.require(.conversationStart, workspace: workspaceID)
        return found.map { LaunchDirectory(id: $0.id, path: display($0.url)) }
    }

    public func listing(workspaceID: String, rootID: String, path: String, access: SessionAccess) async throws -> LaunchDirectoryListing {
        try await access.require(.conversationStart, workspace: workspaceID)
        guard let root = try await roots(workspaceID: workspaceID).first(where: { $0.id == rootID }) else {
            throw BridgeError("stale_binding", "This folder is no longer part of the workspace.", status: 409)
        }
        let base = normalized(path)
        let folder = try files.directory(root: root.url.path, relativePath: base)
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var names: [String] = []
        // A link counts only when it is a folder that stays inside the root.
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            guard (try? files.directory(root: root.url.path, relativePath: (base.isEmpty ? "" : base + "/") + entry.lastPathComponent)) != nil else { continue }
            names.append(entry.lastPathComponent)
            if names.count > Self.listingLimit { break }
        }
        names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        try await access.require(.conversationStart, workspace: workspaceID)
        let truncated = names.count > Self.listingLimit
        return LaunchDirectoryListing(rootID: rootID, path: base, directories: Array(names.prefix(Self.listingLimit)), truncated: truncated)
    }

    /// Records the intent before cmux is asked; a lost reply is reported as unknown and never retried.
    public func start(workspaceID: String, request: StartSessionRequest, access: SessionAccess) async throws -> StartSessionReceipt {
        let workspace = workspaceID.lowercased()
        let commandLine = AgentCommandLine()
        let prompt = try commandLine.validatedPrompt(request.prompt)
        guard prompt != nil || !request.agent.requiresPrompt else { throw BridgeError("prompt_required", "Codex needs a first message to start its conversation.") }
        // Only a digest of the message enters the durable record, as with sends.
        var payloadFields: [String: JSONValue] = ["root": .string(request.rootID), "path": .string(normalized(request.path)), "agent": .string(request.agent.rawValue)]
        if let prompt { payloadFields["prompt"] = .string(IdentityCryptography().digest(Data(prompt.utf8))) }
        let payload: JSONValue = .object(payloadFields)
        let signature = try MutationLedger.fingerprint(action: "session.start", resource: workspace, payload: payload)
        if let prior = try await mutations.prior(clientID: access.clientID, operationID: request.operationID, fingerprint: signature) {
            return try await replay(prior, access: access)
        }
        try await access.require(.conversationStart, workspace: workspace)
        _ = try await folder(workspaceID: workspace, rootID: request.rootID, path: request.path)
        try await access.require(.conversationStart, workspace: workspace)
        // Recheck after actor suspension so simultaneous duplicates cannot both open a terminal.
        if let prior = try await mutations.begin(clientID: access.clientID, operationID: request.operationID, fingerprint: signature,
                                                 workspaceID: workspace, capability: .conversationStart) {
            return try await replay(prior, access: access)
        }
        // The folder and the grant are read again after the durable write, right before cmux acts.
        let target = try await folder(workspaceID: workspace, rootID: request.rootID, path: request.path)
        let row = try await workspaceRow(workspace)
        try await access.require(.conversationStart, workspace: workspace)
        do {
            var params: [String: JSONValue] = [
                "workspace_id": .string(workspace), "type": .string("terminal"), "working_directory": .string(target.path),
                "initial_input": .string(commandLine.line(request.agent, prompt: prompt) + "\r"), "focus": .bool(false)]
            if row["backend"].string == "cmux-tui" {
                // A daemon runs the fixed command itself and deduplicates by key, so a retried write cannot open two terminals.
                params["launch_agent"] = .string(request.agent.rawValue)
                if let prompt { params["launch_prompt"] = .string(prompt) }
                params["operation_key"] = .string(IdentityCryptography().digest(Data((access.clientID + ":" + request.operationID.uuidString).utf8)))
            }
            let result = try await cmux.request("surface.create", params: params)
            guard let surface = result["surface_id"].string, UUID(uuidString: surface) != nil else {
                throw BridgeError("outcome_unknown", "cmux did not confirm the new terminal; check the workspace before trying again.", status: 409)
            }
            let receipt = try await mutations.complete(clientID: access.clientID, operationID: request.operationID)
            return StartSessionReceipt(operationID: receipt.operationID, accepted: receipt.accepted, surfaceID: surface.lowercased())
        } catch {
            throw BridgeError("outcome_unknown", "The new terminal may or may not exist; check the workspace before trying again.", status: 409)
        }
    }

    private func replay(_ prior: MutationLedger.Entry, access: SessionAccess) async throws -> StartSessionReceipt {
        try await access.require(prior.capability, workspace: prior.workspaceID)
        guard let receipt = prior.receipt else { throw BridgeError("outcome_unknown", "Check the workspace before starting another session.", status: 409) }
        return StartSessionReceipt(operationID: receipt.operationID, accepted: receipt.accepted, surfaceID: nil)
    }

    private func folder(workspaceID: String, rootID: String, path: String) async throws -> URL {
        guard let root = try await roots(workspaceID: workspaceID).first(where: { $0.id == rootID }) else {
            throw BridgeError("stale_binding", "This folder is no longer part of the workspace.", status: 409)
        }
        return try files.directory(root: root.url.path, relativePath: normalized(path))
    }

    /// The workspace's own directory, then the folders of its conversations, most recent first, then its other
    /// terminals' folders (a daemon workspace has no directory of its own).
    func roots(workspaceID: String) async throws -> [(id: String, url: URL)] {
        let workspace = workspaceID.lowercased()
        let row = try await workspaceRow(workspace)
        let conversations = try await sessions().filter { $0.workspaceID?.lowercased() == workspace }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        let terminals = (row["directories"].array ?? []).map(\.string)
        var found: [(id: String, url: URL)] = []
        for candidate in [row["current_directory"].string] + conversations.map(\.cwd) + terminals {
            guard let candidate, !candidate.isEmpty, let url = try? files.projectRoot(candidate),
                  !found.contains(where: { $0.url.path == url.path }) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            found.append((SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined(), url))
            if found.count == Self.rootLimit { break }
        }
        return found
    }

    private func workspaceRow(_ workspace: String) async throws -> JSONValue {
        guard UUID(uuidString: workspace) != nil else { throw BridgeError("invalid_input", "Use an explicit workspace UUID.") }
        let rows = try await cmux.request("workspace.list", params: [:])["workspaces"].array ?? []
        guard let row = rows.first(where: { $0["id"].string?.lowercased() == workspace.lowercased() }) else {
            throw BridgeError("not_found", "The workspace no longer exists.", status: 404)
        }
        return row
    }

    private func normalized(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }
    private func display(_ url: URL) -> String {
        url.path.hasPrefix(home.path + "/") ? "~" + url.path.dropFirst(home.path.count) : url.path
    }
}
