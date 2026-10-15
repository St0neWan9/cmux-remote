import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

private actor CollidingDesktop: CmuxControlling {
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            return .object(["sessions": .array([
                .object(["session_id": .string("AAAA-dup"), "title": .string("first")]),
                .object(["session_id": .string("aaaa-DUP"), "title": .string("same id, other case")]),
                .object(["title": .string("no id")]),
                .object(["session_id": .string("bbbb-unique"), "title": .string("fine")])
            ])])
        default: return .object([:])
        }
    }
}

/// One ambiguous or unidentified row must not take every other session off the phone.
@Suite struct InventoryCollisionTests {
    @Test func collidingRowsAreLeftOutWhileTheRestIsListed() async throws {
        let router = CmuxBackendRouter(desktop: CollidingDesktop(), discovery: TuiSocketDiscovery(directories: []), factory: { _ in
            TuiControlAdapter(client: TuiResourceFixture(), transcripts: .init(claudeRoot: URL(fileURLWithPath: "/missing"), codexRoot: URL(fileURLWithPath: "/missing")))
        })
        let listed = try await router.request("vault.sessions", params: [:])
        let ids = listed["sessions"].array?.compactMap { $0["session_id"].string }
        #expect(ids == ["bbbb-unique"])
        #expect(listed["backend_errors"].array?.contains(.string("identity_collision")) == true)
    }
}
