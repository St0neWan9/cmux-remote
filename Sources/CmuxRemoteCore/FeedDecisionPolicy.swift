import Foundation

/// Matches public Feed capabilities so a mode which cmux cannot deliver never becomes an active button.
public struct FeedDecisionPolicy: Sendable {
    public init() {}
    public func modes(for item: JSONValue) -> [FeedDecisionMode] {
        let kind = item["kind"].string ?? ""
        let all = FeedDecisionMode.allCases.filter { $0.supports(kind: kind) }
        if let supported = item["available_modes"].array {
            let modes = Set(supported.compactMap(\.string))
            return all.filter { modes.contains($0.rawValue) }
        }
        guard kind == "permissionRequest" else { return all }
        let source = (item["source"].string ?? "").lowercased()
        // These companions support Claude/Codex. Unknown sources get only bounded, one-off decisions.
        guard source == "claude" || source == "codex" else { return all.filter { [.once, .deny].contains($0) } }
        if source == "claude" { return all.filter { $0 != .bypass } }
        guard let raw = item["tool_input_capabilities"].string ?? item["tool_input"].string else {
            return all.filter { $0 != .bypass }
        }
        guard let data = raw.data(using: .utf8), let caps = try? JSONDecoder().decode(JSONValue.self, from: data), caps.object != nil else { return [.deny] }
        let rawDecisions = caps["available_decisions"].array ?? caps["availableDecisions"].array
        let decisions = rawDecisions.map { Set($0.compactMap { $0.string ?? $0.object?.keys.sorted().first }) }
        let method = caps["app_server_method"].string
        if method == "item/permissions/requestApproval" { return all.filter { $0 != .bypass } }
        let once = decisions?.contains("accept") ?? true
        let always = decisions?.contains("acceptForSession") ?? true
        let amendment = caps["proposed_execpolicy_amendment"] != .null && (decisions?.contains("acceptWithExecpolicyAmendment") ?? true)
        let network = !(caps["proposed_network_policy_amendments"].array ?? []).isEmpty && (decisions?.contains("applyNetworkPolicyAmendment") ?? true)
        let allowAll = method == "item/commandExecution/requestApproval" && (amendment || network)
        return all.filter {
            switch $0 { case .once: return once; case .always: return always; case .all: return allowAll; case .deny: return true; default: return false }
        }
    }
}
