import SwiftUI

/// General launch behavior: automatic start at login and a silent, menu-bar-only launch.
struct GeneralSettingsView: View {
    @Bindable var launch: MacLaunchPreferences
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.general.launchAtLogin", bundle: .interface)) {
                Toggle(String(localized: "mac.general.enabled", bundle: .interface), isOn: Binding(
                    get: { launch.launchAtLogin },
                    set: { launch.setLaunchAtLogin($0) }))
                    .labelsHidden().toggleStyle(.checkbox)
                MacPreferenceNote(text: String(localized: "mac.general.launchAtLogin.hint", bundle: .interface))
                if launch.launchFailed {
                    MacPreferenceNote(text: String(localized: "mac.error.launchService", bundle: .interface))
                }
            }
            MacPreferenceRow(title: String(localized: "mac.general.silentLaunch", bundle: .interface)) {
                Toggle(String(localized: "mac.general.enabled", bundle: .interface), isOn: $launch.silentLaunch)
                    .labelsHidden().toggleStyle(.checkbox)
                MacPreferenceNote(text: String(localized: "mac.general.silentLaunch.hint", bundle: .interface))
            }
        }
    }
}
