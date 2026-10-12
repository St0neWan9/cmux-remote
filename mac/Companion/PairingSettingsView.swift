import SwiftUI
import CmuxRemoteMac

/// New-device pairing: an explicit workspace allow-list, then an expiring QR for exactly that scope.
struct PairingSettingsView: View {
    @Bindable var model: MacSharingModel
    private let design = MacDesignTokens()
    var body: some View {
        MacPreferencePage {
            if let link = model.qrLink {
                MacPreferenceRow(title: String(localized: "mac.pairing.qrLabel", bundle: .interface), topAligned: true) {
                    HStack(alignment: .top, spacing: 16) {
                        PairingQRCodeView(link: link)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "mac.pairing.scanHint", bundle: .interface)).fixedSize(horizontal: false, vertical: true)
                            Text(model.selectedWorkspaces.sorted().map(workspaceName).joined(separator: ", ")).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let expiry = model.expiresAt {
                                (Text(String(localized: "mac.pairing.expires", bundle: .interface) + " ")
                                    + Text(Date(timeIntervalSince1970: Double(expiry)), format: Date.FormatStyle(date: .omitted, time: .shortened)))
                                    .foregroundStyle(.secondary)
                            }
                            Button(String(localized: "mac.pairing.close", bundle: .interface)) { Task { await model.closePairing() } }.disabled(model.busy).fixedSize().padding(.top, 4)
                        }
                    }
                }
            } else {
                MacPreferenceRow(title: String(localized: "mac.pairing.allowed", bundle: .interface), topAligned: true) {
                    Table(items) {
                        TableColumn(String(localized: "mac.column.workspace", bundle: .interface)) { item in Text(item.title).lineLimit(1).help(item.title) }
                        TableColumn(String(localized: "mac.pairing.allow", bundle: .interface)) { item in
                            Toggle(item.title, isOn: Binding(get: { model.selectedWorkspaces.contains(item.id) },
                                set: { if $0 { model.selectedWorkspaces.insert(item.id) } else { model.selectedWorkspaces.remove(item.id) } }))
                                .labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                        }.width(56)
                    }.tableStyle(.bordered(alternatesRowBackgrounds: true)).frame(height: design.tableHeight)
                    MacPreferenceNote(text: String(localized: model.workspaces.isEmpty ? "mac.share.noWorkspaces" : "mac.pairing.workspaceHint", bundle: .interface))
                }
                MacPreferenceRow(title: "") {
                    Button(String(localized: "mac.pairing.open", bundle: .interface)) { Task { await model.openPairing() } }
                        .disabled(!model.isSharing || model.selectedWorkspaces.isEmpty || model.busy).fixedSize()
                    if !model.isSharing { MacPreferenceNote(text: String(localized: "mac.error.pairingSelection", bundle: .interface)) }
                }
            }
        }
    }
    private var items: [MacTableItem] {
        model.workspaces.compactMap { workspace in
            workspace["id"].string.map { MacTableItem(id: $0.lowercased(), title: workspace["title"].string ?? String(localized: "mac.untitled", bundle: .interface)) }
        }
    }
    private func workspaceName(_ id: String) -> String {
        model.workspaces.first { $0["id"].string?.lowercased() == id.lowercased() }?["title"].string ?? id
    }
}
