import Foundation
import CmuxRemoteCore

extension FeedDecisionMode {
    var localizedTitle: String {
        switch self {
        case .once: return String(localized: "feed.mode.once")
        case .always: return String(localized: "feed.mode.always")
        case .all: return String(localized: "feed.mode.all")
        case .bypass: return String(localized: "feed.mode.bypass")
        case .deny: return String(localized: "feed.mode.deny")
        case .ultraplan: return String(localized: "feed.mode.ultraplan")
        case .bypassPermissions: return String(localized: "feed.mode.bypassPermissions")
        case .autoAccept: return String(localized: "feed.mode.autoAccept")
        case .manual: return String(localized: "feed.mode.manual")
        }
    }
    var explanation: String {
        switch self {
        case .once: return String(localized: "feed.effect.once")
        case .always: return String(localized: "feed.effect.always")
        case .all: return String(localized: "feed.effect.all")
        case .bypass: return String(localized: "feed.effect.bypass")
        case .deny: return String(localized: "feed.effect.deny")
        case .ultraplan: return String(localized: "feed.effect.ultraplan")
        case .bypassPermissions: return String(localized: "feed.effect.bypassPermissions")
        case .autoAccept: return String(localized: "feed.effect.autoAccept")
        case .manual: return String(localized: "feed.effect.manual")
        }
    }
}
