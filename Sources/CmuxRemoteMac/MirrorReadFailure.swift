import Foundation
import CmuxRemoteCore

/// Marks only unavailable remote reads as reconnectable; identity and permission failures stay final.
struct MirrorReadFailure: Sendable {
    func normalize(_ error: any Error) -> any Error {
        if let url = error as? URLError,
           [.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet, .timedOut].contains(url.code) {
            return unavailable()
        }
        if let bridge = error as? BridgeError, ["socket_unavailable", "outcome_unknown"].contains(bridge.code) { return unavailable() }
        return error
    }
    private func unavailable() -> BridgeError {
        BridgeError("mirror_remote_unavailable", "The remote Bridge is temporarily unavailable.", status: 503)
    }
}
