import Foundation

/// A provider-neutral arrangement of terminals inside one space. Layout is
/// presentation only; it never grants access to a terminal.
public struct LayoutSnapshot: Codable, Sendable, Equatable {
    public let providerID: String
    public let spaceID: String
    public let revision: String
    public let nodes: [LayoutNode]

    public init(providerID: String, spaceID: String, revision: String, nodes: [LayoutNode]) {
        self.providerID = providerID; self.spaceID = spaceID; self.revision = revision; self.nodes = nodes
    }
}

/// One node in a layout tree: a terminal, a split, a pane, a window or a layer.
public struct LayoutNode: Codable, Sendable, Equatable {
    public let id: String
    /// "terminal", "split", "pane", "window", "layer" or a newer provider value.
    public let kind: String
    public let terminalID: String?
    public let parentID: String?
    public let title: String?
    public let direction: String?
    public let ratio: Double?
    public let rect: [Double]?

    public init(id: String, kind: String, terminalID: String? = nil, parentID: String? = nil,
                title: String? = nil, direction: String? = nil, ratio: Double? = nil, rect: [Double]? = nil) {
        self.id = id; self.kind = kind; self.terminalID = terminalID; self.parentID = parentID
        self.title = title; self.direction = direction; self.ratio = ratio; self.rect = rect
    }
}
