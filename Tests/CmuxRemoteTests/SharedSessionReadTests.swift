import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

/// A daemon that takes a while to list its sessions and counts how often it is asked.
private actor SlowListingCmux: CmuxControlling {
    private(set) var listings = 0
    let delay: Duration
    init(delay: Duration) { self.delay = delay }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            listings += 1
            try await Task.sleep(for: delay)
            return .object(["sessions": .array([.object(["session_id": .string("managed"), "agent": .string("claude"), "title": .string("managed"), "cwd": .string("/example/project")])])])
        case "chat.sessions.dump":
            return .object(["sessions": .array([.object(["session_id": .string("managed"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string("idle")])])])
        default: return .object([:])
        }
    }
}

/// A page's requests arrive together; each authorizes against a session read, and the daemon answers reads in turn.
@Suite struct SharedSessionReadTests {
    @Test func requestsArrivingTogetherShareOneRead() async throws {
        let cmux = SlowListingCmux(delay: .milliseconds(300))
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        // The history, preview, models and list a page asks for at once.
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 { group.addTask { try await service.sessions().count } }
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }
        #expect(counts == [1, 1, 1, 1, 1])
        #expect(await cmux.listings == 1, "Concurrent callers each listed every session again")
        // Once that read is done, the next caller reads afresh rather than reusing an old result.
        _ = try await service.sessions()
        #expect(await cmux.listings == 2)
    }

    /// The router reads the sessions to check a request's scope; the read it serves must not list them all again.
    @Test func aReadAfterTheScopeCheckReusesItsListing() async throws {
        let cmux = SlowListingCmux(delay: .milliseconds(1))
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let access = SessionAccess(clientID: "phone") { _, _ in }
        _ = try await service.sessions()  // the router's scope check
        _ = try await service.models(id: "managed", discovered: true, access: access)
        #expect(await cmux.listings == 1, "The model list read every session again after the scope check")
        // Without a scope check just before it, a read still authorizes against a fresh listing.
        _ = try await service.models(id: "managed", access: access)
        #expect(await cmux.listings == 2)
    }

    @Test func aFailedReadIsNotKeptForTheNextCaller() async throws {
        actor Flaky: CmuxControlling {
            var calls = 0
            func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
                guard method == "vault.sessions" else { return .object([:]) }
                calls += 1
                if calls == 1 { throw BridgeError("socket_unavailable", "cmux is restarting", status: 503) }
                return .object(["sessions": .array([])])
            }
        }
        let service = SessionService(cmux: Flaky(), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await #expect(throws: BridgeError.self) { _ = try await service.sessions() }
        #expect(try await service.sessions().isEmpty)
    }
}
