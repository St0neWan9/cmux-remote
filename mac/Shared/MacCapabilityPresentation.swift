import Foundation
import CmuxRemoteCore

struct MacCapabilityPresentation {
    func name(_ capability: ClientCapability) -> String {
        switch capability {
        case .workspaceRead: return String(localized: "mac.capability.workspaces", bundle: .interface)
        case .conversationRead: return String(localized: "mac.capability.conversations", bundle: .interface)
        case .projectRead: return String(localized: "mac.capability.projects", bundle: .interface)
        case .conversationControl: return String(localized: "mac.capability.send", bundle: .interface)
        case .feedRead: return String(localized: "mac.capability.actions", bundle: .interface)
        case .feedReply: return String(localized: "mac.capability.reply", bundle: .interface)
        case .terminalRead: return String(localized: "mac.capability.terminals", bundle: .interface)
        case .terminalInput: return String(localized: "mac.capability.input", bundle: .interface)
        }
    }
}
