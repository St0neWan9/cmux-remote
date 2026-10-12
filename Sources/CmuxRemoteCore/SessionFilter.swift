import Foundation

/// Read-only discovery filters never launch a session or broaden its host provenance.
public enum SessionFilter: String, CaseIterable, Sendable {
    case all, working, readOnly
    public func matches(_ session: SessionDescriptor, query: String, workspaceID: String?) -> Bool {
        if let workspaceID, session.workspaceID?.lowercased() != workspaceID.lowercased() { return false }
        switch self {
        case .all: break
        case .working: if !session.state.hasPrefix("working") { return false }
        case .readOnly: if session.writable { return false }
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || [session.title, session.agent, session.cwd ?? ""].contains { $0.localizedStandardContains(term) }
    }
}
