import Foundation

/// A Mac row in the drawer footer; only display facts, never its client or grant.
struct SidebarHost: Identifiable {
    let id: String
    let name: String
    let canReadFeed: Bool
    let failed: Bool
}
