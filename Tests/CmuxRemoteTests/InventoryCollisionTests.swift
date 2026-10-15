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

private actor ResumedSessionDesktop: CmuxControlling {
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        guard method == "vault.sessions" else { return .object([:]) }
        func row(_ file: String, _ modified: String) -> JSONValue {
            .object(["session_id": .string("01a13ac8-0af7"), "agent": .string("codex"), "cwd": .string("/work/ios"), "file": .string(file), "modified": .string(modified)])
        }
        return .object(["sessions": .array([row("rollout-10-14.jsonl", "2026-10-14T16:36:32Z"), row("rollout-10-15.jsonl", "2026-10-15T04:15:09Z"),
                                            .object(["session_id": .string("other"), "agent": .string("claude"), "cwd": .string("/work")])])])
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
    /// A resumed Codex session appears once per transcript file; it is listed once, as its newest file.
    @Test func aResumedSessionIsListedOnceByItsNewestTranscript() async throws {
        let router = CmuxBackendRouter(desktop: ResumedSessionDesktop(), discovery: TuiSocketDiscovery(directories: []), factory: { _ in
            TuiControlAdapter(client: TuiResourceFixture(), transcripts: .init(claudeRoot: URL(fileURLWithPath: "/missing"), codexRoot: URL(fileURLWithPath: "/missing")))
        })
        let rows = try await router.request("vault.sessions", params: [:])["sessions"].array ?? []
        #expect(rows.count == 2)
        #expect(rows.first { $0["session_id"].string == "01a13ac8-0af7" }?["file"].string == "rollout-10-15.jsonl")
    }
}
