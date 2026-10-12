import Foundation
import CmuxRemoteCore
import CmuxRemoteMac

actor ReconciliationRemoteFixture: MirrorRemoteControlling {
    var snapshot: MirrorWorkspaceSnapshot
    var epoch = "producer-1"
    var failure: String?
    func failReads(_ code: String?) { failure = code }
    var holdReplay = false
    var replayGate: CheckedContinuation<Void, Never>?
    nonisolated let replayStarted = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func holdNextReplay() { holdReplay = true }
    func releaseReplay() { replayGate?.resume(); replayGate = nil }
    init(_ snapshot: MirrorWorkspaceSnapshot) { self.snapshot = snapshot }
    func change(_ snapshot: MirrorWorkspaceSnapshot) { self.snapshot = snapshot }
    func replaceRuntime() { epoch = "producer-2" }
    func workspace(_ id: String) async throws -> MirrorWorkspaceSnapshot {
        if let failure { throw BridgeError(failure, "Fixture unavailable", status: 503) }; return snapshot
    }
    func replay(workspaceID: String, surfaceID: String) async throws -> MirrorTerminalSnapshot {
        if let failure { throw BridgeError(failure, "Fixture unavailable", status: 503) }
        let captured = epoch
        if holdReplay {
            holdReplay = false
            await withCheckedContinuation { continuation in replayGate = continuation; replayStarted.continuation.yield(()) }
        }
        return .init(workspaceID: workspaceID, surfaceID: surfaceID, runtimeEpoch: captured, columns: 80, rows: 24, bytes: Data("source".utf8))
    }
    func input(workspaceID: String, surfaceID: String, request: MirrorInputRequest) async throws -> MutationReceipt {
        .init(operationID: request.operationID, accepted: true)
    }
}
