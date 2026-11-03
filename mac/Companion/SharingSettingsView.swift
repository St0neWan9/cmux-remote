import SwiftUI
import AppKit
import CmuxRemoteMac

/// Sharing switch and endpoint facts; the switch reflects the service's reported state, not the click.
struct SharingSettingsView: View {
    @Bindable var model: MacSharingModel
    /// The Bridge stores at most this many; the button stops before a rejected save.
    private static let folderLimit = 32
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
            MacPreferenceRow(title: String(localized: "mac.share.folders", bundle: .interface), topAligned: true) {
                ForEach(model.allowedDirectories, id: \.self) { folder in
                    HStack(spacing: 8) {
                        Text(folder).lineLimit(1).truncationMode(.middle).help(folder)
                        Spacer(minLength: 0)
                        Button {
                            Task { await model.saveAllowedDirectories(model.allowedDirectories.filter { $0 != folder }) }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).disabled(model.busy)
                            .accessibilityLabel(String(format: String(localized: "mac.share.folders.remove", bundle: .interface), folder))
                    }
                }
                HStack(spacing: 8) {
                    Button(String(localized: "mac.share.folders.add", bundle: .interface)) { choose() }.fixedSize()
                        .disabled(model.busy || model.allowedDirectories.count >= Self.folderLimit)
                    if model.allowedDirectories.count >= Self.folderLimit {
                        MacPreferenceNote(text: String(format: String(localized: "mac.share.folders.full", bundle: .interface), Self.folderLimit))
                    }
                }
                MacPreferenceNote(text: String(localized: "mac.share.folders.hint", bundle: .interface))
            }
            MacPreferenceRow(title: String(localized: "mac.share.certificate", bundle: .interface)) {
                Text(model.status["certificate"].string ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// A folder is chosen by the standard panel; the Bridge canonicalizes it and returns the display form.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "mac.share.folders.add", bundle: .interface)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = chosen.path
        let display = path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        guard !model.allowedDirectories.contains(display) else { return }
        Task { await model.saveAllowedDirectories(model.allowedDirectories + [display]) }
    }
}
