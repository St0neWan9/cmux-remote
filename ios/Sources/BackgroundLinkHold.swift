import UIKit

/// Keeps the app running for the short while iOS allows after it leaves the foreground, so a quick switch to
/// another app does not cost every Mac's link.
///
/// A suspended app's sockets are torn down within seconds, and every return dialed every Mac again: the page said
/// it was reconnecting each time, and a relay dial plus the reads behind it took several seconds more. Holding the
/// app for iOS's background allowance keeps the link through a glance at another app; a longer absence still ends
/// in a suspension, and the return dials again as before.
@MainActor final class BackgroundLinkHold {
    private var task: UIBackgroundTaskIdentifier = .invalid
    /// Whether the hold that ended last lasted the whole absence. Asked by more than one place on the same return,
    /// in no fixed order, so it answers the same until the next hold begins.
    private var lasted = false

    /// Starts holding; iOS ending the allowance first releases it, and the links may then be gone.
    func begin() {
        release()
        lasted = false
        task = UIApplication.shared.beginBackgroundTask(withName: "cmux-remote.link") { [weak self] in
            MainActor.assumeIsolated { self?.release() }
        }
    }
    /// Ends the hold on a return to the foreground, and says whether it lasted until now.
    func end() -> Bool {
        if task != .invalid { lasted = true; release() }
        return lasted
    }
    private func release() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task); task = .invalid
    }
}
