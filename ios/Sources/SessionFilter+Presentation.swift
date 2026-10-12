import Foundation
import CmuxRemoteCore

extension SessionFilter {
    var localizedTitle: String {
        switch self {
        case .all: return String(localized: "sessions.filter.all")
        case .working: return String(localized: "sessions.filter.working")
        case .readOnly: return String(localized: "sessions.filter.readOnly")
        }
    }
}
