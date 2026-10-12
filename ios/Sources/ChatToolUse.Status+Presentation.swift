import Foundation
import CmuxAgentChat

extension ChatToolUse.Status {
    var localizedTitle: String {
        switch self {
        case .running: return String(localized: "chat.tool.running")
        case .succeeded: return String(localized: "chat.tool.succeeded")
        case .failed: return String(localized: "chat.tool.failed")
        }
    }
}
