import Foundation
import CmuxRemoteCore

/// Whether a failed enrollment status poll is worth asking again until the request expires. The poll only reads,
/// so a link that dropped mid-request is safe to repeat; the client reports every POST lost in flight as
/// `outcome_unknown`, which a relay reconnect produces routinely.
struct EnrollmentPollRetry {
    private static let networkCodes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
    private static let linkCodes: Set<String> = ["outcome_unknown", "connection_failed", "socket_unavailable"]
    func shouldRetry(_ error: any Error, expiresAt: Int, now: Int) -> Bool {
        guard expiresAt > now else { return false }
        if let network = error as? URLError { return Self.networkCodes.contains(network.code) }
        if let failure = error as? BridgeError { return Self.linkCodes.contains(failure.code) }
        return false
    }
}
