import SwiftUI
import CmuxRemoteMac

/// Native preference rows for optional cloud reachability; secrets remain in private local files.
struct RelaySettingsRows: View {
    @Bindable var model: MacSharingModel
    var body: some View {
        Group {
            MacPreferenceRow(title: String(localized: "mac.relay.origin", bundle: .interface)) {
                TextField(String(localized: "mac.relay.originPlaceholder", bundle: .interface), text: $model.relayOrigin).labelsHidden().textFieldStyle(.roundedBorder)
                    .disabled(model.isSharing || model.busy)
                MacPreferenceNote(text: String(localized: "mac.relay.hint", bundle: .interface))
            }
            MacPreferenceRow(title: String(localized: "mac.relay.keyFile", bundle: .interface)) {
                TextField(String(localized: "mac.relay.keyPlaceholder", bundle: .interface), text: $model.relayKeyFile).labelsHidden().textFieldStyle(.roundedBorder)
                    .disabled(model.isSharing || model.busy)
                HStack {
                    Button(String(localized: "mac.relay.save", bundle: .interface)) { Task { await model.saveRelay() } }
                    Button(String(localized: "mac.relay.remove", bundle: .interface)) { Task { await model.removeRelay() } }
                        .disabled(model.status["relay"]["origin"].string == nil)
                }.disabled(model.isSharing || model.busy)
            }
            if let state = model.status["relay"]["state"].string {
                MacPreferenceRow(title: String(localized: "mac.relay.status", bundle: .interface)) {
                    Text(String(localized: String.LocalizationValue("mac.relay.state." + state), bundle: .interface)).foregroundStyle(.secondary)
                    if let code = model.status["relay"]["error_code"].string {
                        MacPreferenceNote(text: MacErrorPresentation.message(code))
                    }
                }
            }
        }
    }
}
