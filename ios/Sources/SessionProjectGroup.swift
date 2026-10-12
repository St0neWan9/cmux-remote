import Foundation
import CmuxRemoteCore

/// Immutable display groups retain every cmux-bound conversation and its existing order.
struct SessionProjectGroup: Identifiable {
    let id: String
    let name: String?
    var sessions: [SessionDescriptor]

    static func make(from sessions: [SessionDescriptor]) -> [Self] {
        var groups: [Self] = []
        var positions: [String: Int] = [:]
        for session in sessions {
            let directory = session.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).standardizedFileURL }
            let id = directory?.path ?? "unassigned"
            if let index = positions[id] { groups[index].sessions.append(session) }
            else {
                positions[id] = groups.count
                groups.append(Self(id: id, name: directory?.lastPathComponent, sessions: [session]))
            }
        }
        return groups
    }
}
