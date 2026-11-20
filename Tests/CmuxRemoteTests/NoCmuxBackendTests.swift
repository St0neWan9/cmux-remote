import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct NoCmuxBackendTests {
    /// A Rex-only Bridge still answers the generic inventory routes, but never fakes a cmux write.
    @Test func emptyInventoryKeepsProviderRoutesUsable() async throws {
        let backend = NoCmuxBackend()
        let workspaces = try await backend.request("workspace.list", params: [:])
        #expect(workspaces["workspaces"].array?.isEmpty == true)
        let sessions = try await backend.request("vault.sessions", params: [:])
        #expect(sessions["sessions"].array?.isEmpty == true)
        let feed = try await backend.request("feed.list", params: [:])
        #expect(feed["items"].array?.isEmpty == true)
        let ping = try await backend.request("system.ping", params: [:])
        #expect(ping["active_backends"].int == 0)
        await #expect(throws: BridgeError.self) {
            _ = try await backend.request("workspace.create", params: [:])
        }
    }
}
