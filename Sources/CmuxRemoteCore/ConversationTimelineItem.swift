import Foundation
import CmuxAgentChat

/// A nonempty immutable transcript row or consecutive activity group.
///
/// The row's messages and its operation count are stored rather than computed: a timeline asks for both every
/// time it evaluates a row, and rebuilding the array (and filtering it) on each read is work a scroll pays for
/// on every frame it moves.
public struct ConversationTimelineItem: Identifiable, Sendable, Equatable {
    public let first: ChatMessage
    public let following: [ChatMessage]
    public let isActivity: Bool
    public let messages: [ChatMessage]
    public let operationCount: Int
    public var id: String { first.id }
    public init(first: ChatMessage, following: [ChatMessage] = [], isActivity: Bool) {
        self.first = first; self.following = following; self.isActivity = isActivity
        let all = [first] + following
        messages = all
        operationCount = all.reduce(0) { count, message in
            if case .thought = message.kind { return count }
            return count + 1
        }
    }
}
