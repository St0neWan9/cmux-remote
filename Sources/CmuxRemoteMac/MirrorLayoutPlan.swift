import Foundation
import CmuxRemoteCore

/// Validated terminal-only split tree. Browser-only branches are omitted explicitly.
public indirect enum MirrorLayoutPlan: Sendable {
    case pane([MirrorSurface])
    case split(direction: String, first: MirrorLayoutPlan, second: MirrorLayoutPlan)
    public var firstSurface: MirrorSurface {
        switch self { case .pane(let values): return values[0]; case .split(_, let first, _): return first.firstSurface }
    }
    /// Returns terminal order within the validated split tree.
    public var surfaces: [MirrorSurface] {
        switch self { case .pane(let values): return values; case .split(_, let first, let second): return first.surfaces + second.surfaces }
    }
    /// Compares structure and tab order without transient titles or split ratios.
    public var topologySignature: String {
        switch self {
        case .pane(let values): return "(" + values.map(\.id).joined(separator: ",") + ")"
        case .split(let direction, let first, let second): return direction + "[" + first.topologySignature + second.topologySignature + "]"
        }
    }
    public static func make(_ snapshot: MirrorWorkspaceSnapshot) throws -> MirrorLayoutPlan {
        guard !snapshot.surfaces.isEmpty, snapshot.surfaces.count <= 64, Set(snapshot.surfaces.map(\.id)).count == snapshot.surfaces.count,
              snapshot.surfaces.allSatisfy({ $0.id == UUID(uuidString: $0.id)?.uuidString.lowercased() && $0.paneID == UUID(uuidString: $0.paneID)?.uuidString.lowercased() }) else {
            throw BridgeError("invalid_layout", "The terminal layout is empty, duplicated, or too large.")
        }
        let panes = Dictionary(grouping: snapshot.surfaces, by: \.paneID)
        if snapshot.layout == .null {
            // Older hosts expose only pane ordering. Preserve tabs within each pane.
            var seen = Set<String>()
            var plans = snapshot.surfaces.filter { seen.insert($0.paneID).inserted }.map { MirrorLayoutPlan.pane(panes[$0.paneID]!) }
            var result = plans.removeFirst()
            for next in plans { result = .split(direction: "right", first: result, second: next) }
            return result
        }
        var seen = Set<String>()
        guard let plan = try parse(snapshot.layout, panes: panes, seen: &seen, depth: 0), seen == Set(panes.keys) else {
            throw BridgeError("invalid_layout", "The layout does not cover the selected terminals.")
        }
        return plan
    }
    private static func parse(_ value: JSONValue, panes: [String: [MirrorSurface]], seen: inout Set<String>, depth: Int) throws -> MirrorLayoutPlan? {
        guard depth <= 16 else { throw BridgeError("invalid_layout", "The split tree is too deep.") }
        if let id = value["pane"]["id"].string?.lowercased() {
            guard let terminals = panes[id] else { return nil }
            guard seen.insert(id).inserted else { throw BridgeError("invalid_layout", "The split tree repeats a pane.") }
            return .pane(terminals)
        }
        guard let children = value["children"].array, children.count == 2,
              ["horizontal", "vertical"].contains(value["direction"].string ?? "") else { throw BridgeError("invalid_layout", "Unsupported split tree.") }
        let first = try parse(children[0], panes: panes, seen: &seen, depth: depth + 1)
        let second = try parse(children[1], panes: panes, seen: &seen, depth: depth + 1)
        if let first, let second { return .split(direction: value["direction"].string == "horizontal" ? "right" : "down", first: first, second: second) }
        return first ?? second
    }
}
