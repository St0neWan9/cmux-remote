import SwiftUI
import CmuxRemoteMac

/// Sharing switch and endpoint facts; the switch reflects the service's reported state, not the click.
struct SharingSettingsView: View {
    @Bindable var model: MacSharingModel
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.share.label", bundle: .interface)) {
                Toggle(String(localized: "mac.share.enable", bundle: .interface), isOn: Binding(get: { model.isSharing }, set: { enabled in Task { await model.setSharing(enabled) } }))
                    .toggleStyle(.checkbox).disabled(model.busy)
            }
            MacPreferenceRow(title: String(localized: "mac.status", bundle: .interface)) {
                HStack(spacing: 8) {
                    Label {
                        Text(String(localized: model.isSharing ? "mac.share.running" : "mac.share.stopped", bundle: .interface))
                    } icon: {
                        Image(systemName: model.isSharing ? "checkmark.circle.fill" : "circle").foregroundStyle(model.isSharing ? .green : .secondary)
                    }
                    Button(String(localized: "mac.refresh", bundle: .interface)) { Task { await model.refresh() } }.controlSize(.small).disabled(model.busy).fixedSize()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if let code = model.errorCode {
                    Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.isSharing, let address = model.address {
                MacPreferenceRow(title: String(localized: "mac.share.address", bundle: .interface)) {
                    Text("https://" + address + ":" + String(model.port)).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            MacPreferenceRow(title: String(localized: "mac.share.port", bundle: .interface)) {
                TextField(String(localized: "mac.share.port", bundle: .interface), value: $model.port, format: .number.grouping(.never))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 72).disabled(model.isSharing || model.busy)
                MacPreferenceNote(text: String(localized: "mac.share.portHint", bundle: .interface))
            }
            RelaySettingsRows(model: model)
            MacPreferenceRow(title: String(localized: "mac.share.certificate", bundle: .interface)) {
                Text(model.status["certificate"].string ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
