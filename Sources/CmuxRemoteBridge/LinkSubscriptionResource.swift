import Foundation

/// The resources a link subscription may repeat, as named by their `GET` path.
enum LinkSubscriptionResource: Sendable, Equatable {
    case sessionList
    case feed
    case sessionHistory(id: String)
    case sessionPreview(id: String)
    case sessionTask(id: String, task: String)

    init?(uri: String) {
        guard let components = URLComponents(string: uri), components.scheme == nil, components.host == nil else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        if path == ["v2", "sessions"] { self = .sessionList; return }
        if path == ["v2", "feed"] { self = .feed; return }
        if path.count == 5, path[0...1] == ["v2", "sessions"], path[3] == "tasks" { self = .sessionTask(id: path[2], task: path[4]); return }
        guard path.count == 4, path[0...1] == ["v2", "sessions"] else { return nil }
        switch path[3] {
        case "history": self = .sessionHistory(id: path[2])
        case "preview": self = .sessionPreview(id: path[2])
        default: return nil
        }
    }
}
