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
        // The group with the most recent activity leads; ties keep the Mac's workspace order; unbound conversations last.
        func latest(_ group: Self) -> Date { group.sessions.compactMap(\.updatedAt).max() ?? .distantPast }
        return groups.values.sorted { lhs, rhs in
            if (lhs.id == "unbound") != (rhs.id == "unbound") { return rhs.id == "unbound" }
            if latest(lhs) != latest(rhs) { return latest(lhs) > latest(rhs) }
            return (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
        }
    }
}
