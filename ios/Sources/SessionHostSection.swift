import Foundation
import CmuxRemoteCore

/// One Mac's project groups, in Mac order; group IDs are unique only within their Mac.
struct SessionHostSection: Identifiable {
    let hostID: String
    let hostName: String
    let groups: [SessionProjectGroup]
    var id: String { hostID }
    static func make(links: [HostLink], sessions: [HostedSession]) -> [Self] {
        links.compactMap { link in
            let owned = sessions.filter { $0.hostID == link.id }.map(\.session)
            return owned.isEmpty ? nil : Self(hostID: link.id, hostName: link.name, groups: SessionProjectGroup.make(from: owned))
        }
    }
}
