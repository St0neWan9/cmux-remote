import Foundation
import Darwin
import CmuxRemoteCore

/// Short, credential-free renderings for diagnostic trace lines.
///
/// Errors are reduced to their type and stable code: messages, URLs, headers and bodies never appear,
/// so a trace cannot carry a grant, request proof, relay permit or prompt text.
public struct TraceFormat: Sendable {
    public init() {}
    public func describe(_ error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let failure = error as? BridgeError { return "BridgeError(\(failure.code) \(failure.status))" }
        if let network = error as? URLError {
            var text = "URLError(\(network.code.rawValue) \(name(network.code)))"
            if let underlying = network.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain { text += " " + posix(underlying.code) }
            return text
        }
        let failure = error as NSError
        if failure.domain == NSPOSIXErrorDomain { return posix(failure.code) }
        if error is DecodingError { return "DecodingError" }
        if error is EncodingError { return "EncodingError" }
        return "\(failure.domain)(\(failure.code))"
    }
    /// A resource URI without its query, whose values may identify content.
    public func route(_ uri: String) -> String { String(uri.prefix { $0 != "?" }) }
    /// The relay's host name only: the socket URL also names the Mac and role.
    public func origin(_ relay: RelayEndpoint) -> String { URL(string: relay.origin)?.host ?? "relay" }
    public func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now).components
        return Int(elapsed.seconds) * 1000 + Int(elapsed.attoseconds / 1_000_000_000_000_000)
    }
    private func posix(_ code: Int) -> String {
        let names: [Int32: String] = [ENETDOWN: "ENETDOWN", ENETUNREACH: "ENETUNREACH", EHOSTDOWN: "EHOSTDOWN", EHOSTUNREACH: "EHOSTUNREACH",
                                      ECONNREFUSED: "ECONNREFUSED", ECONNRESET: "ECONNRESET", ECONNABORTED: "ECONNABORTED", ENOTCONN: "ENOTCONN",
                                      ETIMEDOUT: "ETIMEDOUT", EPIPE: "EPIPE", EADDRNOTAVAIL: "EADDRNOTAVAIL"]
        return "POSIX(\(code)" + (names[Int32(code)].map { " " + $0 } ?? "") + ")"
    }
    private func name(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut: return "timedOut"
        case .cancelled: return "cancelled"
        case .cannotFindHost: return "cannotFindHost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .networkConnectionLost: return "networkConnectionLost"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .dnsLookupFailed: return "dnsLookupFailed"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .serverCertificateUntrusted: return "serverCertificateUntrusted"
        case .serverCertificateHasBadDate: return "serverCertificateHasBadDate"
        case .serverCertificateNotYetValid: return "serverCertificateNotYetValid"
        case .serverCertificateHasUnknownRoot: return "serverCertificateHasUnknownRoot"
        case .badServerResponse: return "badServerResponse"
        case .userAuthenticationRequired: return "userAuthenticationRequired"
        case .internationalRoamingOff: return "internationalRoamingOff"
        case .dataNotAllowed: return "dataNotAllowed"
        case .callIsActive: return "callIsActive"
        default: return "other"
        }
    }
}
