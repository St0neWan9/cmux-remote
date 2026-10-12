import Foundation

/// Stable failure codes map to localized UI; internal network errors are not displayed.
struct MacErrorPresentation {
    static func message(_ code: String) -> String {
        switch code {
        case "socket_unavailable", "owner_socket_exists": return String(localized: "mac.error.localBridge")
        case "mirror_remote_unavailable": return String(localized: "mac.error.remoteBridge")
        case "sidebar_permission": return String(localized: "mac.error.permission")
        case "scope_denied": return String(localized: "mac.error.scope")
        case "mirror_unsupported", "invalid_layout": return String(localized: "mac.error.unsupported")
        case "stale_binding", "mirror_detached": return String(localized: "mac.error.stale")
        case "mirror_local_changed": return String(localized: "mac.error.localMirror")
        case "native_group_unsupported": return String(localized: "mac.error.nativeGroup")
        case "outcome_unknown": return String(localized: "mac.error.unknown")
        case "receipt_capacity": return String(localized: "mac.error.receiptCapacity")
        case "receipt_storage", "invalid_state": return String(localized: "mac.error.receiptStorage")
        case "host_changed", "invalid_signature", "certificate_mismatch": return String(localized: "mac.error.identity")
        case "enrollment_denied": return String(localized: "mac.error.denied")
        case "enrollment_expired": return String(localized: "mac.error.expired")
        case "enrollment_cancelled": return String(localized: "mac.error.cancelled")
        case "unauthorized": return String(localized: "mac.error.authorization")
        case "enrollment_closed", "enrollment_pending": return String(localized: "mac.error.enrollment")
        default: return String(localized: "mac.error.connection")
        }
    }
}
