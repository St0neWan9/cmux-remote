import Foundation

/// Fixed cmux Feed modes; no decision contains an arbitrary RPC method or command.
public enum FeedDecisionMode: String, Sendable, CaseIterable {
    case once, always, all, bypass, deny, ultraplan, bypassPermissions, autoAccept, manual
    public var needsExplanation: Bool { ![Self.once, .manual, .deny].contains(self) }
    public func supports(kind: String) -> Bool {
        switch kind {
        case "permissionRequest": return [.once, .always, .all, .bypass, .deny].contains(self)
        case "exitPlan": return [.ultraplan, .bypassPermissions, .autoAccept, .manual, .deny].contains(self)
        default: return false
        }
    }
}
