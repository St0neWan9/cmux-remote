import Foundation
import CmuxRemoteCore

extension ClientCapability {
    var localizedTitle: String {
        switch self {
        case .workspaceRead: return String(localized: "capability.workspaceRead")
        case .conversationRead: return String(localized: "capability.conversationRead")
        case .projectRead: return String(localized: "capability.projectRead")
        case .conversationControl: return String(localized: "capability.conversationControl")
        case .feedRead: return String(localized: "capability.feedRead")
        case .feedReply: return String(localized: "capability.feedReply")
        case .terminalRead: return String(localized: "capability.terminalRead")
        case .terminalInput: return String(localized: "capability.terminalInput")
        @unknown default: return String(localized: "capability.additional")
        }
    }
}
