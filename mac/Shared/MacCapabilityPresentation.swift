import Foundation
import CmuxRemoteCore

struct MacCapabilityPresentation {
    func name(_ capability: ClientCapability) -> String {
        switch capability {
        case .workspaceRead: return String(localized: "mac.capability.workspaces")
        case .conversationRead: return String(localized: "mac.capability.conversations")
        case .projectRead: return String(localized: "mac.capability.projects")
        case .conversationControl: return String(localized: "mac.capability.send")
        case .feedRead: return String(localized: "mac.capability.actions")
        case .feedReply: return String(localized: "mac.capability.reply")
        case .terminalRead: return String(localized: "mac.capability.terminals")
        case .terminalInput: return String(localized: "mac.capability.input")
        }
    }
}
