import Foundation
import Testing
import CmuxAgentChat
import CmuxRemoteCore

@Suite struct ConversationTimelineTests {
    private func message(_ id: String, _ seq: Int, _ kind: ChatMessageKind, role: ChatRole = .agent) -> ChatMessage {
        ChatMessage(id: id, seq: seq, role: role, timestamp: Date(timeIntervalSince1970: 0), kind: kind)
    }
    @Test func activityGroupsPreserveEveryDetailAndNeverSwallowProseOrUserPrompts() {
        let messages = [
            message("prompt", 0, .prose(ChatProse(text: "Please investigate")), role: .user),
            message("thinking", 1, .thought(ChatThought(text: "Investigating"))),
            message("read", 2, .toolUse(ChatToolUse(toolName: "Read", summary: "Read README", output: "Details", status: .succeeded))),
            message("reply", 3, .prose(ChatProse(text: "First conclusion"))),
            message("search", 4, .toolUse(ChatToolUse(toolName: "Search", summary: "Search source"))),
            message("next", 5, .prose(ChatProse(text: "Follow up")), role: .user)
        ]
        let items = ConversationTimeline().items(from: messages)
        #expect(items.map(\.id) == ["prompt", "thinking", "reply", "search", "next"])
        #expect(items.flatMap(\.messages) == messages)
        #expect(items[1].operationCount == 1)
        #expect(!items[0].isActivity && !items[2].isActivity && !items[4].isActivity)
    }
    @Test func appendingAToolResultRetainsTheExpandedGroupsIdentity() {
        let first = message("read", 1, .toolUse(ChatToolUse(toolName: "Read", summary: "Read source")))
        let next = message("search", 2, .toolUse(ChatToolUse(toolName: "Search", summary: "Search source")))
        let before = ConversationTimeline().items(from: [first])
        let after = ConversationTimeline().items(from: [first, next])
        #expect(before.first?.id == after.first?.id)
        #expect(after.first?.messages.count == 2)
        #expect(after.first?.operationCount == 2)
    }
}
