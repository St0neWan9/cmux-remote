import Foundation
import Darwin

/// Only an unreachable LAN path may fall back to the relay; identity, TLS pin and protocol failures never do.
struct LinkPathFailure: Sendable {
    func isUnreachable(_ error: any Error) -> Bool {
        if let network = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed].contains(network.code)
        }
        // WebSocket tasks often surface the socket's own errno rather than a URLError.
        let failure = error as NSError
        return failure.domain == NSPOSIXErrorDomain && [ENETDOWN, ENETUNREACH, EHOSTDOWN, EHOSTUNREACH, ECONNREFUSED, ECONNRESET, ENOTCONN, ETIMEDOUT].map(Int.init).contains(failure.code)
    }
}
