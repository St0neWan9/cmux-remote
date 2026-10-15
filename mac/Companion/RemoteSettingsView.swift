import SwiftUI

/// One settings window; the preference toolbar selects a page and the window fits that page's height.
struct RemoteSettingsView: View {
    let app: MacAppModel
    let sectionChanged: () -> Void
    let openLogs: () -> Void
    var body: some View {
        Group {
            if app.serviceError != nil && app.section != "advanced" {
                MacPreferencePage { MacSetupRows(app: app) }
            } else {
                switch app.section {
                case "pairing": PairingSettingsView(model: app.sharing)
                case "devices": DevicesSettingsView(model: app.sharing)
                case "connect": CompanionView(model: app.remote)
                case "advanced": MacAdvancedView(app: app, openLogs: openLogs)
                default: SharingSettingsView(model: app.sharing)
                }
            }
        }
        // Rebuilding the page tree re-reads every localized string after a language change.
        .id(app.language).environment(\.locale, app.language.locale)
        .fixedSize()
        .onChange(of: app.section) { sectionChanged() }
    }
}
