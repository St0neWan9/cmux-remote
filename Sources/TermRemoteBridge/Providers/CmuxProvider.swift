import Foundation
import CryptoKit
import TermRemoteCore
import CmuxTerminalReplay

/// The official cmux desktop app as a term remote provider. It exposes
/// workspaces as spaces and terminal surfaces as terminals. Conversation
/// methods remain on the existing cmux service until the directory publishes
/// them generically.
public actor CmuxProvider: TerminalProvider {
    private let identity: ProviderDescriptor
    private let cmux: any CmuxControlling
    private let mirrors: RemoteMirrorService
    private var terminalCache: [String: TerminalDescriptor] = [:]

    public init(descriptor: ProviderDescriptor, cmux: any CmuxControlling, mirrors: RemoteMirrorService) {
        self.identity = descriptor; self.cmux = cmux; self.mirrors = mirrors
    }

    public var descriptor: ProviderDescriptor { identity }

    public func spaces() async throws -> [SpaceDescriptor] {
        let value = try await cmux.request("workspace.list", params: [:])
        let rows = value["workspaces"].array ?? []
        guard rows.count <= 256 else { throw BridgeError("provider_invalid", "cmux returned too many workspaces.", status: 502) }
        return rows.compactMap { row in
            guard let id = row["id"].string?.lowercased(), UUID(uuidString: id) != nil else { return nil }
            let title = row["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SpaceDescriptor(id: id, providerID: identity.id,
                                   title: title.flatMap { $0.isEmpty ? nil : $0 } ?? id, kind: "workspace")
        }
    }

    public func terminals(spaceID: String) async throws -> [TerminalDescriptor] {
        let workspace = try await mirrors.workspace(id: spaceID)
        let result = workspace.surfaces.map { surface in
            TerminalDescriptor(id: surface.id.lowercased(), providerID: identity.id, spaceID: spaceID.lowercased(),
                               title: surface.title, kind: "terminal", state: "unknown", layoutID: surface.paneID.lowercased())
        }
        for item in result { terminalCache[item.id] = item }
        return result
    }

    public func layout(spaceID: String) async throws -> LayoutSnapshot {
        let workspace = try await mirrors.workspace(id: spaceID)
        var nodes: [LayoutNode] = []
        var panes = Set<String>()
        for surface in workspace.surfaces {
            let pane = surface.paneID.lowercased()
            if panes.insert(pane).inserted {
                nodes.append(LayoutNode(id: pane, kind: "pane"))
            }
            nodes.append(LayoutNode(id: "terminal:" + surface.id.lowercased(), kind: "terminal",
                                    terminalID: surface.id.lowercased(), parentID: pane, title: surface.title))
        }
        let signature = nodes.map { [$0.id, $0.kind, $0.terminalID ?? "", $0.parentID ?? "", $0.title ?? ""].joined(separator: "\u{0}") }
            .joined(separator: "\u{1}")
        return LayoutSnapshot(providerID: self.identity.id, spaceID: spaceID.lowercased(),
                              revision: Self.digest(signature), nodes: nodes)
    }

    public func terminal(_ id: String) async throws -> TerminalDescriptor {
        let key = id.lowercased()
        if let cached = terminalCache[key] { return cached }
        guard UUID(uuidString: key) != nil else { throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404) }
        for space in try await spaces() {
            guard let items = try? await terminals(spaceID: space.id) else { continue }
            if let match = items.first(where: { $0.id == key }) { return match }
        }
        throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404)
    }

    public func snapshot(terminalID: String) async throws -> TerminalSnapshot {
        let terminal = try await terminal(terminalID)
        let replay = try await mirrors.replay(workspaceID: terminal.spaceID, surfaceID: terminal.id)
        var text = ""
        if let grid = replay.renderGrid, let data = try? JSONEncoder().encode(grid),
           let frame = try? JSONDecoder().decode(MobileTerminalRenderGridFrame.self, from: data) {
            text = frame.plainRows().joined(separator: "\n")
        }
        guard !text.isEmpty || !replay.bytes.isEmpty else {
            throw BridgeError("mirror_unsupported", "The terminal screen could not be read.", status: 422)
        }
        let revision = Self.digest(replay.runtimeEpoch) + ":" + Self.digest(replay.bytes)
        return TerminalSnapshot(providerID: identity.id, spaceID: terminal.spaceID, terminalID: terminal.id,
                                revision: revision, columns: replay.columns, rows: replay.rows,
                                format: text.isEmpty ? "vt" : "text", text: text, vt: replay.bytes,
                                truncated: false)
    }

    public func send(_ input: TerminalInputRequest, clientID: String, terminalID: String,
                     authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt {
        let terminal = try await terminal(terminalID)
        let current = try await mirrors.replay(workspaceID: terminal.spaceID, surfaceID: terminal.id)
        let text = input.submit == true ? input.text + "\r" : input.text
        guard !text.isEmpty else { throw BridgeError("invalid_input", "Terminal input must be non-empty.", status: 400) }
        let request = MirrorInputRequest(runtimeEpoch: current.runtimeEpoch, text: text, operationID: input.operationID)
        return try await mirrors.input(workspaceID: terminal.spaceID, surfaceID: terminal.id,
                                       clientID: clientID, request: request, authorize: authorize)
    }

    private static func digest(_ text: String) -> String {
        digest(Data(text.utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
