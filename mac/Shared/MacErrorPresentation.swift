import Foundation

/// Stable failure codes map to localized UI; internal network errors are not displayed.
struct MacErrorPresentation {
    static func message(_ code: String) -> String {
        switch code {
        case "setup_required": return String(localized: "mac.error.setup", bundle: .interface)
        case "setup_storage": return String(localized: "mac.error.setupStorage", bundle: .interface)
        case "resident_starting", "sharing_busy": return String(localized: "mac.error.starting", bundle: .interface)
        case "resident_missing", "resident_failed": return String(localized: "mac.error.resident", bundle: .interface)
        case "sharing_start_failed", "sharing_stopped", "invalid_endpoint": return String(localized: "mac.error.sharing", bundle: .interface)
        case "sharing_unsupported", "not_found": return String(localized: "mac.error.sharingUpgrade", bundle: .interface)
        case "pairing_selection": return String(localized: "mac.error.pairingSelection", bundle: .interface)
        case "invalid_state_path": return String(localized: "mac.error.statePath", bundle: .interface)
        case "socket_unavailable", "owner_socket_exists": return String(localized: "mac.error.localBridge", bundle: .interface)
        case "mirror_remote_unavailable": return String(localized: "mac.error.remoteBridge", bundle: .interface)
        case "sidebar_permission": return String(localized: "mac.error.permission", bundle: .interface)
        case "scope_denied": return String(localized: "mac.error.scope", bundle: .interface)
        case "mirror_unsupported", "invalid_layout": return String(localized: "mac.error.unsupported", bundle: .interface)
        case "stale_binding", "mirror_detached": return String(localized: "mac.error.stale", bundle: .interface)
        case "mirror_local_changed": return String(localized: "mac.error.localMirror", bundle: .interface)
        case "native_group_unsupported": return String(localized: "mac.error.nativeGroup", bundle: .interface)
        case "outcome_unknown": return String(localized: "mac.error.unknown", bundle: .interface)
        case "receipt_capacity": return String(localized: "mac.error.receiptCapacity", bundle: .interface)
        case "receipt_storage", "invalid_state": return String(localized: "mac.error.receiptStorage", bundle: .interface)
        case "host_changed", "invalid_signature", "certificate_mismatch": return String(localized: "mac.error.identity", bundle: .interface)
        case "enrollment_denied": return String(localized: "mac.error.denied", bundle: .interface)
        case "enrollment_expired": return String(localized: "mac.error.expired", bundle: .interface)
        case "enrollment_cancelled": return String(localized: "mac.error.cancelled", bundle: .interface)
        case "unauthorized": return String(localized: "mac.error.authorization", bundle: .interface)
        case "enrollment_closed", "enrollment_pending": return String(localized: "mac.error.enrollment", bundle: .interface)
        default: return String(localized: "mac.error.connection", bundle: .interface)
        }
    }
}
