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
                        // The code's white quiet zone is invisible in light mode but still counts as layout, so the
                        // visible square sat a quiet zone below the row's title and first line of text. Pulling the
                        // zone out of the layout puts the square itself on the row's top edge; the white margin still
                        // surrounds the code for scanning. It then rises to the label's glyphs, not the label's frame.
                        PairingQRCodeView(link: link)
                            .padding(.top, -design.qrQuietZone + design.labelTopPadding + design.textGlyphInset - design.qrOpticalLift)
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
                    // The label already drops this far below the row's top; the text and the code start level with it.
                    .padding(.top, design.labelTopPadding)
                }
            } else {
                MacPreferenceRow(title: String(localized: "mac.pairing.allowed", bundle: .interface), topAligned: true) {
                    Table(items) {
                        TableColumn(String(localized: "mac.column.workspace", bundle: .interface)) { item in
                            // The row is the control: the checkbox carries its label across the whole cell, so a
                            // click anywhere on a workspace flips it, the same as in the approval list.
                            Toggle(isOn: Binding(get: { model.selectedWorkspaces.contains(item.id) },
                                set: { setAllowed($0, for: item) })) {
                                Text(item.title).lineLimit(1).help(item.title)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .toggleStyle(.checkbox).disabled(model.busy)
                        }
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
    private func setAllowed(_ allowed: Bool, for item: MacTableItem) {
        if allowed { model.selectedWorkspaces.insert(item.id) } else { model.selectedWorkspaces.remove(item.id) }
    }
    private func workspaceName(_ id: String) -> String {
        model.workspaces.first { $0["id"].string?.lowercased() == id.lowercased() }?["title"].string ?? id
    }
}
