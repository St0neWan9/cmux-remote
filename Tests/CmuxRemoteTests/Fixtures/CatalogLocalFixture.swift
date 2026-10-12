import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

actor CatalogLocalFixture: CmuxControlling {
    let window = "99999999-9999-9999-9999-999999999999"
    var surfaces: [String: [String]] = [:]
    var selected: String?
    var commands: [String] = []
    var calls: [String] = []
    var loseCreate = false
    var explicitSelection = false
    var workspaceWindows: [String: String] = [:]
    var selectionWindows: [String] = []
    var nextTreeDelay = 0
    var hiddenWorkspace: String?
    var treeDelay = 0
    var currentWindow: String?
    func focusWindow(_ id: String) { currentWindow = id }
    func delayNextTreePublication(reads: Int) { nextTreeDelay = reads }
    func allowExplicitSelection() { explicitSelection = true }
    func close(_ id: String) { surfaces[id] = nil; workspaceWindows[id] = nil }
    func move(_ id: String, window: String) { workspaceWindows[id] = window }
    func select(_ id: String) { selected = id }
    func loseNextCreate() { loseCreate = true }
    func addForeignSurface(_ workspace: String) { surfaces[workspace]?.append(UUID().uuidString) }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        calls.append(method)
        switch method {
        case "workspace.create":
            #expect(params["focus"]?.bool == false)
            let ws = UUID().uuidString, surface = UUID().uuidString
            surfaces[ws] = [surface]; commands.append(params["initial_command"]?.string ?? "")
            workspaceWindows[ws] = window
            if nextTreeDelay > 0 { hiddenWorkspace = ws; treeDelay = nextTreeDelay; nextTreeDelay = 0 }
            if loseCreate { loseCreate = false; throw BridgeError("outcome_unknown", "Created; receipt lost") }
            return .object(["workspace_id": .string(ws), "surface_id": .string(surface), "window_id": .string(window)])
        case "system.tree":
            let hidden = treeDelay > 0 ? hiddenWorkspace : nil
            if treeDelay > 0 { treeDelay -= 1 }
            let windows = Set(workspaceWindows.values).filter {
                currentWindow == nil || params["all_windows"]?.bool == true || $0 == currentWindow
            }
            return .object(["windows": .array(windows.map { w in .object(["id": .string(w), "workspaces": .array(surfaces.keys.filter { workspaceWindows[$0] == w && $0 != hidden }.map { .object(["id": .string($0)]) })]) })])
        case "workspace.list": return .object(["window_id": .string(window), "workspaces": .array(surfaces.keys.filter { params["window_id"]?.string == nil || workspaceWindows[$0] == params["window_id"]?.string }.map { .object(["id": .string($0), "selected": .bool($0 == selected)]) })])
        case "surface.list":
            let ws = params["workspace_id"]!.string!
            return .object(["workspace_id": .string(ws), "surfaces": .array((surfaces[ws] ?? []).map { .object(["id": .string($0), "pane_id": .string($0)]) })])
        case "surface.split", "surface.create":
            let ws = params["workspace_id"]!.string!, id = UUID().uuidString
            surfaces[ws]?.append(id); commands.append(params["initial_command"]?.string ?? "")
            #expect(params["focus"]?.bool == false)
            return .object(["workspace_id": .string(ws), "surface_id": .string(id)])
        case "surface.action", "surface.reorder": return .object([:])
        case "workspace.select":
            if !explicitSelection { Issue.record("Inventory or lazy attachment stole selection") }
            selected = params["workspace_id"]?.string
            if let window = params["window_id"]?.string { selectionWindows.append(window) }
            return .object([:])
        default: return .object([:])
        }
    }
}
