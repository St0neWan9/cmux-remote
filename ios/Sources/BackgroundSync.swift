import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// The app-refresh task that keeps running conversations current while the app is in the background.
///
/// iOS decides when it runs, and how often it honours the interval below follows the app's own use; the pass is the
/// same one the foreground runs for conversations off screen, so switching to one shows what it said meanwhile.
///
/// This is a poll, not a push: the wake dials, reads and lets the app be suspended again, so a message that arrives
/// while the app is away is read at the next wake rather than as it arrives.
enum BackgroundSync {
    static let identifier = "cmux-remote.sync"
    static let enabledKey = "backgroundSync"
    /// The earliest start iOS is asked for. It is a floor, not a schedule: the system may run the task later, and
    /// skips it entirely in Low Power Mode or when the app has been force quit.
    static let spacing: TimeInterval = 60

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
