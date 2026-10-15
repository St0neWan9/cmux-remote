import SwiftUI

/// Applying a directory changes which resident is controlled, never its identity or grants.
struct MacAdvancedView: View {
    @Bindable var app: MacAppModel
    let openLogs: () -> Void
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.stateDirectory", bundle: .interface)) {
                HStack(spacing: 8) {
                    TextField(String(localized: "mac.stateDirectory", bundle: .interface), text: $app.statePath).labelsHidden().textFieldStyle(.roundedBorder)
                    Button(String(localized: "mac.apply", bundle: .interface)) { Task { await app.applyStatePath() } }.disabled(app.starting).fixedSize()
                }
                MacPreferenceNote(text: String(localized: "mac.stateDirectory.hint", bundle: .interface))
            }
            MacPreferenceRow(title: String(localized: "mac.logs.title", bundle: .interface)) {
                Button(String(localized: "mac.logs.open", bundle: .interface)) { openLogs() }.fixedSize()
                MacPreferenceNote(text: String(localized: "mac.logs.hint", bundle: .interface))
            }
            MacSetupRows(app: app)
        }
    }
}
