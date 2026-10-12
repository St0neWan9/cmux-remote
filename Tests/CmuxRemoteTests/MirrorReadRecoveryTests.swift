import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteMac

private actor UnavailableMirrorOwner: LocalMacControlling {
    func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        throw BridgeError("mirror_remote_unavailable", "Unavailable", status: 503)
    }
}

private actor RecoveringSnapshotOwner: CmuxControlling {
    var failures: Int
    let code: String
    private(set) var calls = 0
    init(failures: Int, code: String) { self.failures = failures; self.code = code }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        #expect(method == "mirror.replay")
        calls += 1
        if failures > 0 { failures -= 1; throw BridgeError(code, "fixture") }
        let snapshot = MirrorTerminalSnapshot(workspaceID: "workspace", surfaceID: "surface",
            runtimeEpoch: "same-producer", columns: 80, rows: 24, bytes: Data("recovered".utf8))
        return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(snapshot))
    }
}

@Suite struct MirrorReadRecoveryTests {
    @Test(arguments: ["socket_unavailable", "outcome_unknown", "mirror_remote_unavailable"])
    func viewerRecoversAfterRepeatedReadFailures(code: String) async throws {
        let owner = RecoveringSnapshotOwner(failures: 12, code: code)
        let snapshot = try await MirrorSnapshotReader(owner: owner, wait: { duration in
            #expect(duration > .zero && duration <= .seconds(3))
        }).read([:])
        #expect(snapshot.runtimeEpoch == "same-producer")
        #expect(await owner.calls == 13)
    }
    @Test(arguments: ["scope_denied", "unauthorized", "host_changed", "stale_binding"])
    func viewerNeverRetriesAuthorityOrRuntimeFailures(code: String) async {
        let owner = RecoveringSnapshotOwner(failures: 12, code: code)
        do {
            _ = try await MirrorSnapshotReader(owner: owner, wait: { _ in Issue.record("Unexpected retry") }).read([:])
            Issue.record("Expected final error")
        } catch { #expect((error as? BridgeError)?.code == code) }
        #expect(await owner.calls == 1)
    }
    @Test(.timeLimit(.minutes(1))) func closingViewerCancelsReconnectBackoff() async {
        let owner = RecoveringSnapshotOwner(failures: 12, code: "mirror_remote_unavailable")
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            try await MirrorSnapshotReader(owner: owner, wait: { _ in
                started.continuation.yield(())
                try await Task.sleep(for: .seconds(60))
            }).read([:])
        }
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(await owner.calls == 1)
    }
    @Test func existingViewerReadCodeDoesNotEnableWriteRetries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize()
        let service = SessionService(cmux: ReconciliationLocalFixture(), home: directory, transcriptRoots: [])
        let router = OwnerControlRouter(authority: try state.authority(name: "Fixture"), service: service, mac: UnavailableMirrorOwner())
        let read = await router.respond(.object(["method": .string("mirror.replay"), "params": .object([:])]))
        #expect(read["error"]["code"].string == "socket_unavailable")
        let write = await router.respond(.object(["method": .string("mirror.input"), "params": .object([:])]))
        #expect(write["error"]["code"].string == "mirror_remote_unavailable")
    }
    @Test(arguments: [URLError.Code.networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .timedOut])
    func unavailableReadsGetAStableReconnectCode(code: URLError.Code) {
        let failure = MirrorReadFailure().normalize(URLError(code)) as? BridgeError
        #expect(failure?.code == "mirror_remote_unavailable")
    }
    @Test(arguments: ["scope_denied", "unauthorized", "invalid_signature", "host_changed", "invalid_response", "stale_binding"])
    func authorityAndContentErrorsNeverBecomeReconnectable(code: String) {
        let failure = MirrorReadFailure().normalize(BridgeError(code, "fixture")) as? BridgeError
        #expect(failure?.code == code)
    }
    @Test func pinFailureAndCancellationStayFinal() {
        for code in [URLError.Code.serverCertificateUntrusted, .cancelled] {
            let failure = MirrorReadFailure().normalize(URLError(code)) as? URLError
            #expect(failure?.code == code)
        }
    }
    @Test(.timeLimit(.minutes(1))) func deadlineCancelsReadRatherThanStartingAnotherAttempt() async throws {
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let cancelled = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let reading = Task {
            try await MirrorReadDeadline(timeout: .milliseconds(50)).run {
                started.continuation.yield(())
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled.continuation.yield(()); throw error }
                return 1
            }
        }
        var begin = started.stream.makeAsyncIterator(); _ = await begin.next()
        do { _ = try await reading.value; Issue.record("Expected a read deadline") }
        catch { #expect((error as? URLError)?.code == .timedOut) }
        var end = cancelled.stream.makeAsyncIterator(); _ = await end.next()
    }
}
