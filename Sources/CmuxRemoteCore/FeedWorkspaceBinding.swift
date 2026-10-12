import Foundation

/// Binds a Feed workstream only to exact agent/session identities already established by cmux.
public struct FeedWorkspaceBinding: Sendable {
    public init() {}
    public func workspace(for item: JSONValue, sessions: [SessionDescriptor]) -> String? {
        let explicit = item["workspace_id"].string
        guard let raw = item["workstream_id"].string else { return explicit }
        let candidates: [SessionDescriptor]
        if raw.hasPrefix("cmux-feed-v1:") {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, let agentData = Data(base64Encoded: String(parts[1])), let sessionData = Data(base64Encoded: String(parts[2])),
                  let agent = String(data: agentData, encoding: .utf8), let id = String(data: sessionData, encoding: .utf8) else { return nil }
            candidates = sessions.filter { $0.agent == agent && $0.id == id }
        } else {
            candidates = sessions.filter { raw == $0.agent + "-" + $0.id }
        }
        let bindings = Set(candidates.compactMap(\.workspaceID).map { $0.lowercased() })
        guard bindings.count == 1, let bound = bindings.first else { return nil }
        if let explicit, explicit.lowercased() != bound { return nil }
        return bound
    }
}
