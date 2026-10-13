import Foundation

/// How the conversation list and drawer arrange conversations; shared by both and remembered.
enum SessionSortMode: String, CaseIterable, Identifiable {
    case workspace
    case time
    static let storageKey = "sessionSortMode"
    var id: String { rawValue }
    var title: String { String(localized: self == .workspace ? "sessions.sort.workspace" : "sessions.sort.time") }
    var symbol: String { self == .workspace ? "macwindow" : "clock" }
}
