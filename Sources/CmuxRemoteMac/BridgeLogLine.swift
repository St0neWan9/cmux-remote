import Foundation
import CmuxRemoteBridge

/// One complete line of `bridge.log`, with the level the Bridge wrote after the timestamp.
public struct BridgeLogLine: Sendable, Equatable, Identifiable {
    /// Position in the excerpt it was read in; stable only within that excerpt.
    public let id: Int
    public let text: String
    /// `nil` only for a leading line whose level cannot be recognised.
    public let level: BridgeLog.Level?
    public init(id: Int, text: String, level: BridgeLog.Level?) { self.id = id; self.text = text; self.level = level }
    /// Lines look like `2026-10-15T13:40:12.305+08:00 INFO [relay] message`. A line without a level, such as the
    /// continuation of a message that contained a newline, keeps the level of the line above it, so a level filter
    /// never separates a message from its own continuation.
    public static func parse(_ texts: [String]) -> [BridgeLogLine] {
        var previous: BridgeLog.Level?
        return texts.enumerated().map { index, text in
            let fields = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            let level = fields.count > 1 ? BridgeLog.Level(rawValue: fields[1].lowercased()) : nil
            if let level { previous = level }
            return BridgeLogLine(id: index, text: text, level: level ?? previous)
        }
    }
}
