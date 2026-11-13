import Foundation

/// Which conversations `/clear` replaced, and when.
///
/// `/clear` starts a new Agent session in the same terminal and records the command at the top of the new session's
/// transcript; nothing names the session it replaced. That one is the conversation the terminal held last: among the
/// others on the same terminal, the one whose last message comes latest before the clear. A conversation used again
/// after the clear (resumed later) was not left behind by it, and one a hook proves live never is.
struct ClearedSessions: Sendable {
    struct Entry: Sendable {
        let id: String
        let surfaceID: String?
        /// The daemon's hooks bind it to its terminal now; a prompt on the screen alone does not count.
        let live: Bool
        let lastMessage: Date?
        /// When `/clear` opened this conversation's own session.
        let clearedFrom: Date?
    }
    func times(_ entries: [Entry]) -> [String: Date] {
        var bySurface: [String: [Entry]] = [:]
        for entry in entries { if let surface = entry.surfaceID?.lowercased() { bySurface[surface, default: []].append(entry) } }
        var cleared: [String: Date] = [:]
        for (_, sharing) in bySurface where sharing.count > 1 {
            for successor in sharing {
                guard let at = successor.clearedFrom else { continue }
                guard let replaced = sharing.filter({ $0.id != successor.id && ($0.lastMessage.map { $0 <= at } ?? false) })
                    .max(by: { ($0.lastMessage!, $0.id) < ($1.lastMessage!, $1.id) }), !replaced.live else { continue }
                // An older conversation can be the latest one before a later clear too, when the one between them was
                // resumed afterwards; the earliest clear is the one that left it behind.
                cleared[replaced.id] = min(cleared[replaced.id] ?? at, at)
            }
        }
        return cleared
    }
}
