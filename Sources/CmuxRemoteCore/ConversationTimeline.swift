import CmuxAgentChat

/// Groups only consecutive agent activities, preserving transcript order and prose boundaries.
public struct ConversationTimeline: Sendable {
    public init() {}
    public func items(from messages: [ChatMessage]) -> [ConversationTimelineItem] {
        var result: [ConversationTimelineItem] = []
        var activities: [ChatMessage] = []
        for message in messages {
            let activity: Bool
            if message.role == .user { activity = false }
            else {
                switch message.kind {
                case .thought, .toolUse, .terminal, .fileEdit: activity = true
                default: activity = false
                }
            }
            if activity { activities.append(message) }
            else {
                if let first = activities.first { result.append(ConversationTimelineItem(first: first, following: Array(activities.dropFirst()), isActivity: true)); activities.removeAll(keepingCapacity: true) }
                result.append(ConversationTimelineItem(first: message, isActivity: false))
            }
        }
        if let first = activities.first { result.append(ConversationTimelineItem(first: first, following: Array(activities.dropFirst()), isActivity: true)) }
        return result
    }
}
