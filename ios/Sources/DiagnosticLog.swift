import Foundation

/// In-process ring buffer for diagnostic events. Survives link reconnects.
/// Thread-safe: all mutations go through the actor.
actor DiagnosticLog {
    static let shared = DiagnosticLog()
    private var entries: [Entry] = []
    private let capacity = 500

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
    }

    enum Level: String, Sendable { case debug, info, warning, error }

    func append(_ level: Level, category: String, _ message: String) {
        let entry = Entry(timestamp: Date(), level: level, category: category, message: message)
        if entries.count >= capacity { entries.removeFirst() }
        entries.append(entry)
    }

    func all() -> [Entry] { entries }
    func clear() { entries.removeAll() }
}

/// Fire-and-forget diagnostic logging — callers do not need async/await.
func diagLog(_ level: DiagnosticLog.Level = .info, category: String, _ message: String) {
    Task { await DiagnosticLog.shared.append(level, category: category, message) }
}

/// The trace a `RemoteClient` reports into: one line per dial, path outcome, link loss and failed request,
/// tagged with the Mac so several links stay apart. Lines that carry an error are warnings.
func diagLinkTrace(host: String) -> @Sendable (String) -> Void {
    let tag = String(host.prefix(8))
    return { line in diagLog(line.contains("error=") || line.contains("timeout") ? .warning : .info, category: "link", line + " host=" + tag) }
}
