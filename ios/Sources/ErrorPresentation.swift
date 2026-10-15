import Foundation
import CmuxRemoteCore

struct ErrorPresentation {
    /// A lost or unreachable link, which the connection bar shows and retries instead of a red line on the page.
    func isConnectivity(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if (error as NSError).domain == NSPOSIXErrorDomain { return true }
        // These Bridge and relay codes are transient connection failures, not application errors.
        // They resolve on the next reconnect without user action, so the connection bar handles them.
        return ["relay_unavailable", "connection_failed",
                "bridge_offline", "bridge_starting", "bridge_replaced",
                "invalid_proof", "replayed_request", "relay_configuration",
                "capacity"].contains((error as? BridgeError)?.code ?? "")
    }
    func message(_ error: any Error) -> String {
        if let network = error as? URLError {
            return String(localized: network.code == .timedOut ? "error.network_timeout" : "error.network")
        }
        if (error as NSError).domain == NSPOSIXErrorDomain { return String(localized: "error.network") }
        let code = (error as? BridgeError)?.code
        switch code {
        case "relay_unavailable": return String(localized: "error.relay")
        case "invalid_endpoint": return String(localized: "error.relay_origin")
        case "unauthorized", "scope_denied": return String(localized: "error.authorization")
        case "enrollment_closed", "enrollment_expired", "request_not_found", "request_finished": return String(localized: "error.enrollment")
        case "host_changed", "invalid_identity", "invalid_signature", "invalid_grant": return String(localized: "error.identity")
        case "invalid_proof", "replayed_request": return String(localized: "error.epoch")
        case "draft_storage_failed": return String(localized: "error.draft_storage")
        case "keychain_failed": return String(localized: "error.keychain")
        case "outcome_unknown": return String(localized: "error.outcome_unknown")
        case "read_only", "stale_binding": return String(localized: "error.read_only")
        case "input_busy": return String(localized: "error.input_busy")
        case "socket_denied", "socket_unavailable": return String(localized: "error.socket")
        case "history_unavailable", "history_too_large": return String(localized: "error.history")
        case "file_forbidden", "unsupported_file": return String(localized: "error.file")
        case "invalid_input", "too_large": return String(localized: "error.input_value")
        case "project_unavailable": return String(localized: "error.project")
        case "session_not_found": return String(localized: "error.read_only")
        case "operation_conflict": return String(localized: "error.operation_conflict")
        case "receipt_capacity": return String(localized: "error.receipt_capacity")
        case "receipt_storage", "invalid_state": return String(localized: "error.receipt_storage")
        case "journal_unavailable": return String(localized: "error.journal")
        case "operation_not_found": return String(localized: "error.operation_missing")
        case "speech_permission": return String(localized: "voice.permission")
        case "speech_unavailable": return String(localized: "voice.unavailable")
        case "speech_too_long": return String(localized: "voice.too_long")
        case "image_unavailable": return String(localized: "error.image_unavailable")
        case "invalid_image": return String(localized: "error.image")
        case "image_load_failed": return String(localized: "error.image_load")
        case "request_expired": return String(localized: "error.expired")
        default:
            // Temporary: log the error code in the banner so it can be identified and handled.
            if let code { return "[" + code + "] " + String(localized: "error.connection") }
            return String(localized: "error.connection")
        }
    }
}
