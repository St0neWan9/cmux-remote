import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

actor ReconciliationLocalFixture: CmuxControlling {
    let workspaceID = "44444444-4444-4444-4444-444444444444"
    var panes: [String: [String]] = [:]
    var commands: [String] = []
    var closed: [String] = []
    var methods: [String] = []
    var directions: [String] = []
    var selections = 0
    var failMove = false
    var titles: [String: String] = [:]
    var repurposed = Set<String>()
    var delayedSurface: String?
    var publicationReads = 0
    var nextPublicationReads = 0
    func delayNextCreation(reads: Int) { nextPublicationReads = reads }
    nonisolated let renames = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(32))
    func repurpose(_ id: String) { repurposed.insert(id) }
    func addForeignTerminal() -> String {
        let id = UUID().uuidString
        let pane = panes.keys.first!
        panes[pane]!.append(id)
        return id
    }
    func loseNextMove() { failMove = true }
    func pane(containing id: String) -> String? { panes.first { $0.value.contains(id) }?.key }
    func remove(_ id: String) {
        guard let pane = pane(containing: id) else { return }
        panes[pane]!.removeAll { $0 == id }
        if panes[pane]!.isEmpty { panes[pane] = nil }
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        methods.append(method)
        if method != "workspace.create", method != "workspace.list" {
            #expect(params["workspace_id"]?.string == workspaceID)
        }
        switch method {
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspaceID)])])])
        case "workspace.select": selections += 1; return .object([:])
        case "workspace.create", "surface.create", "surface.split":
            let surface = UUID().uuidString
            let pane = method == "surface.create" ? params["pane_id"]!.string! : UUID().uuidString
            if method == "surface.create", let existing = panes[pane], !existing.isEmpty { panes[pane]!.insert(surface, at: 1) }
            else { panes[pane, default: []].append(surface) }
            commands.append(params["initial_command"]?.string ?? "")
            if method == "surface.create", nextPublicationReads > 0 {
                delayedSurface = surface; publicationReads = nextPublicationReads; nextPublicationReads = 0
            }
            return .object(["workspace_id": .string(workspaceID), "surface_id": .string(surface), "pane_id": .string(pane)])
        case "surface.list":
            let hidden = publicationReads > 0 ? delayedSurface : nil
            if publicationReads > 0 { publicationReads -= 1 }
            return .object(["workspace_id": .string(workspaceID), "surfaces": .array(panes.flatMap { pane, ids in ids.filter { $0 != hidden }.enumerated().map { index, id in
                .object(["id": .string(id), "pane_id": .string(pane), "index": .number(Double(index))])
            } })])
        case "surface.action":
            titles[params["surface_id"]!.string!] = params["title"]?.string
            if let title = params["title"]?.string { renames.continuation.yield(title) }
            return .object([:])
        case "surface.input_state": return .object(["workspace_id": .string(workspaceID), "surface_id": params["surface_id"]!, "terminal": .bool(true), "agent": .bool(repurposed.contains(params["surface_id"]!.string!))])
        case "surface.move":
            #expect(params["focus"]?.bool == false)
            let id = params["surface_id"]!.string!, pane = params["pane_id"]!.string!
            remove(id); panes[pane, default: []].append(id)
            if failMove { failMove = false; throw BridgeError("outcome_unknown", "Move happened; receipt lost") }
            return .object(["surface_id": .string(id), "pane_id": .string(pane)])
        case "surface.split_off":
            #expect(params["focus"]?.bool == false)
            let id = params["surface_id"]!.string!, pane = UUID().uuidString
            remove(id); panes[pane] = [id]; directions.append(params["direction"]!.string!)
            return .object(["surface_id": .string(id), "pane_id": .string(pane)])
        case "surface.reorder":
            #expect(params["focus"]?.bool == false)
            let id = params["surface_id"]!.string!, pane = pane(containing: id)!
            panes[pane]!.removeAll { $0 == id }; panes[pane]!.insert(id, at: params["index"]!.int!)
            return .object([:])
        case "surface.close":
            let id = params["surface_id"]!.string!; closed.append(id); remove(id); return .object([:])
        default: return .object([:])
        }
    }
}
