import Foundation

/// Read-only discovery filters never launch a session or broaden its host provenance.
public enum SessionFilter: String, CaseIterable, Sendable {
    case all, working, readOnly
    public func matches(_ session: SessionDescriptor, query: String, workspaceID: String?) -> Bool {
        if let workspaceID, session.workspaceID?.lowercased() != workspaceID.lowercased() { return false }
        switch self {
        case .all: break
        // "Running" means a live Agent you can still talk to, idle or busy; history that cannot be
        // reopened is Read-only instead.
        case .working: if !session.state.hasPrefix("working") && !session.writable { return false }
        case .readOnly: if session.writable { return false }
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || [session.title, session.agent, session.cwd ?? ""].contains { $0.localizedStandardContains(term) }
    }
}
