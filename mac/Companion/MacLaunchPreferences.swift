import Foundation
import Observation
import ServiceManagement

/// Launch behavior the person controls on the General page: system auto-start and a silent start.
@MainActor @Observable final class MacLaunchPreferences {
    private static let silentKey = "silentLaunch"
    private let defaults: UserDefaults
    /// A silent launch shows only the menu bar icon; the settings window waits for an explicit open.
    var silentLaunch: Bool {
        didSet { defaults.set(silentLaunch, forKey: Self.silentKey) }
    }
    /// The system login item is the source of truth, not a stored flag.
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    /// A failed registration or unregistration is shown next to the toggle, not thrown away.
    var launchFailed = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        silentLaunch = defaults.bool(forKey: Self.silentKey)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchFailed = false
        } catch { launchFailed = true }
    }
}
