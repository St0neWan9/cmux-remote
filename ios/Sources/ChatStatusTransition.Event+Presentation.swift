import Foundation
import CmuxAgentChat

extension ChatStatusTransition.Event {
    var localizedTitle: String {
        switch self {
        case .sessionStarted: return String(localized: "chat.status.session_started")
        case .sessionEnded: return String(localized: "chat.status.session_ended")
        case .interrupted: return String(localized: "chat.status.interrupted")
        case .contextCompacted: return String(localized: "chat.status.context_compacted")
        }
    }
}
