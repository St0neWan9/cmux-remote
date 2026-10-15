import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// The app-refresh task that keeps running conversations current while the app is in the background.
///
/// iOS decides when it runs, usually a few times an hour, and gives it about thirty seconds; the pass is the same
/// one the foreground runs for conversations off screen, so switching to one shows what it said meanwhile.
enum BackgroundSync {
    static let identifier = "com.st0newan9.cmux-remote.sync"
    static let enabledKey = "backgroundSync"
    /// iOS treats this as the earliest start; it usually waits longer.
    static let spacing: TimeInterval = 15 * 60

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    #if os(iOS)
    static func schedule() {
        guard enabled else { cancel(); return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: spacing)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { diagLog(.warning, category: "sync", "background refresh not scheduled: \((error as NSError).code)") }
    }

    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
    #endif
}
