import Foundation
import CmuxRemoteMac
import CmuxRemoteCore

actor CatalogGroupFixture: NativeRemoteWorkspaceGrouping {
    var workspaces: [String] = []
    var failNext = false
    func failNextPlacement() { failNext = true }
    func place(workspaceID: String, windowID: String?) async throws {
        if failNext { failNext = false; throw BridgeError("stale_binding", "Native snapshot not yet published") }
        workspaces.append(workspaceID)
    }
}
