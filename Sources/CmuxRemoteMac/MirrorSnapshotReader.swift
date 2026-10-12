import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Keeps an owned viewer alive across transient read failures until cancellation.
struct MirrorSnapshotReader: Sendable {
    let owner: any CmuxControlling
    var wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func read(_ params: [String: JSONValue]) async throws -> MirrorTerminalSnapshot {
        var attempts = 0
        while true {
            try Task.checkCancellation()
            do {
                let value = try await owner.request("mirror.replay", params: params)
                return try JSONDecoder().decode(MirrorTerminalSnapshot.self, from: JSONEncoder().encode(value))
            } catch let error as BridgeError where ["socket_unavailable", "outcome_unknown", "mirror_remote_unavailable"].contains(error.code) {
                // Requests and backoff are bounded; the viewer owns cancellation.
                // Identity, permission and runtime failures leave immediately.
                attempts = min(attempts + 1, 4)
                try await wait(.milliseconds(min(3000, 200 * (1 << attempts))))
            }
        }
    }
}
