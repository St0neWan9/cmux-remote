import Foundation
import CmuxRemoteCore

/// Conversations grouped by their cmux workspace, in the Mac's workspace order; unbound ones come last.
struct SessionWorkspaceGroup: Identifiable {
    let id: String
    /// Nil for conversations no longer bound to a workspace (ended or read-only history).
    let name: String?
    var sessions: [SessionDescriptor]
    static func make(from sessions: [SessionDescriptor], workspaces: [WorkspaceSummary]) -> [Self] {
        let order = Dictionary(workspaces.enumerated().map { ($0.element.id.lowercased(), $0.offset) }, uniquingKeysWith: { first, _ in first })
        let titles = Dictionary(workspaces.map { ($0.id.lowercased(), $0.title) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: Self] = [:]
        for session in sessions {
            let key = session.workspaceID?.lowercased() ?? "unbound"
            groups[key, default: Self(id: key, name: key == "unbound" ? nil : (titles[key] ?? session.title), sessions: [])].sessions.append(session)
        }
        // Known workspaces first in the Mac's order, then workspaces not in its list, then unbound conversations.
        return groups.values.sorted { lhs, rhs in
            func rank(_ group: Self) -> (Int, String) { group.id == "unbound" ? (Int.max, "") : (order[group.id] ?? Int.max - 1, group.name ?? "") }
            return rank(lhs) < rank(rhs)
        }
    }
}
