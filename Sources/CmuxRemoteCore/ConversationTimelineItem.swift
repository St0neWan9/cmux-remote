import Foundation
import CmuxAgentChat

/// A nonempty immutable transcript row or consecutive activity group.
public struct ConversationTimelineItem: Identifiable, Sendable, Equatable {
    public let first: ChatMessage
    public let following: [ChatMessage]
    public let isActivity: Bool
    public var messages: [ChatMessage] { [first] + following }
    public var id: String { first.id }
    public init(first: ChatMessage, following: [ChatMessage] = [], isActivity: Bool) {
        self.first = first; self.following = following; self.isActivity = isActivity
    }
    public var operationCount: Int {
        messages.filter { if case .thought = $0.kind { return false }; return true }.count
    }
}
