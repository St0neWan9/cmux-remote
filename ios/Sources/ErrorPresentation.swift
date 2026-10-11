import Foundation
import CmuxRemoteCore

struct ErrorPresentation {
    func message(_ error: any Error) -> String {
        let code = (error as? BridgeError)?.code
        switch code {
        case "unauthorized", "scope_denied": return String(localized: "error.authorization")
        case "enrollment_closed", "enrollment_expired", "request_not_found", "request_finished": return String(localized: "error.enrollment")
        case "host_changed", "invalid_identity", "invalid_signature", "invalid_grant", "invalid_proof", "replayed_request": return String(localized: "error.identity")
        case "keychain_failed": return String(localized: "error.keychain")
        case "outcome_unknown": return String(localized: "error.outcome_unknown")
        case "read_only", "stale_binding": return String(localized: "error.read_only")
        case "input_busy": return String(localized: "error.input_busy")
        case "socket_denied", "socket_unavailable": return String(localized: "error.socket")
        case "history_unavailable", "history_too_large": return String(localized: "error.history")
        case "file_forbidden", "unsupported_file": return String(localized: "error.file")
        case "request_expired": return String(localized: "error.expired")
        default: return String(localized: "error.connection")
        }
    }
}
