import SwiftUI
import CmuxRemoteMac

/// Host choice and workspace mirroring; terminal work remains in the native cmux workspace.
struct CompanionView: View {
    @Bindable var model: MacCompanionModel
    @State private var workspaceID: String?
    private let design = MacDesignTokens()
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.connect.host", bundle: .interface)) {
                Picker(String(localized: "mac.connect.host", bundle: .interface), selection: hostSelection) {
                    Text(String(localized: "mac.connect.placeholder", bundle: .interface)).tag(String?.none)
                    if !model.connections.isEmpty {
                        Section(String(localized: "mac.connected", bundle: .interface)) {
                            ForEach(Array(model.connections.enumerated()), id: \.offset) { _, connection in
                                if let id = connection["id"].string {
                                    Text(connection["name"].string ?? String(localized: "mac.untitled", bundle: .interface)).tag(Optional("saved:" + id))
                                }
                            }
                        }
                    }
                    if !model.devices.isEmpty {
                        Section(String(localized: "mac.nearby", bundle: .interface)) {
                            ForEach(model.devices) { device in Text(device.host.name).tag(Optional("nearby:" + device.host.id)) }
                        }
                    }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
                if let note = hostNote { MacPreferenceNote(text: note) }
                HStack(spacing: 8) {
                    Button(String(localized: "mac.refresh", bundle: .interface)) { Task { await model.refresh() } }.disabled(model.busy).fixedSize()
                    if let id = savedHostID {
                        Button(String(localized: "mac.forgetHost", bundle: .interface)) { Task { await model.forget(hostID: id) } }
                            .disabled(model.busy).fixedSize().help(String(localized: "mac.forgetHint", bundle: .interface))
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }
            }
            if model.pendingRequestID != nil || statusCode != nil || model.mirroredWorkspaceID != nil {
                MacPreferenceRow(title: String(localized: "mac.status", bundle: .interface)) {
                    if let id = model.pendingRequestID {
                        Label(String(localized: "mac.awaitApproval", bundle: .interface), systemImage: "clock").fixedSize(horizontal: false, vertical: true)
                        Text(id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Button(String(localized: "mac.cancel", bundle: .interface)) { Task { await model.cancelEnrollment() } }.fixedSize()
                    }
                    if let code = statusCode {
                        Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        MacPreferenceNote(text: String(localized: "mac.bridgeHint", bundle: .interface))
                    } else if model.mirroredWorkspaceID != nil {
                        Label {
                            Text(String(localized: "mac.mirrored", bundle: .interface))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
            MacPreferenceRow(title: String(localized: "mac.workspaces", bundle: .interface), topAligned: model.selectedHostID != nil && !model.workspaces.isEmpty) {
                if model.selectedHostID == nil {
                    Text(String(localized: "mac.selectHost", bundle: .interface)).foregroundStyle(.secondary)
                } else if !model.workspaces.isEmpty {
                    Table(workspaceItems, selection: workspaceSelection) {
                        TableColumn(String(localized: "mac.column.workspace", bundle: .interface)) { item in Text(item.title).lineLimit(1).help(item.title) }
                    }.tableStyle(.bordered(alternatesRowBackgrounds: true)).tableColumnHeaders(.hidden).frame(height: design.tableHeight)
                    Button(String(localized: "mac.mirror", bundle: .interface)) {
                        if let id = workspaceSelection.wrappedValue { Task { await model.mirror(workspaceID: id) } }
                    }.disabled(model.busy || workspaceSelection.wrappedValue == nil).fixedSize()
                    MacPreferenceNote(text: String(localized: "mac.snapshotNote", bundle: .interface))
                } else if !model.busy && model.pendingRequestID == nil && model.errorCode == nil {
                    Text(String(localized: "mac.workspaces.empty", bundle: .interface)).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.trustCandidate != nil }, set: { if !$0 { model.declineTrust() } })) {
            if let device = model.trustCandidate {
                HostTrustSheet(name: device.host.name, fingerprint: device.host.certificateSHA256,
                    confirm: { Task { await model.confirmTrust(device) } }, cancel: { model.declineTrust() })
            }
        }
    }
    private var statusCode: String? { model.mirrorErrorCode ?? model.errorCode }
    private var savedHostID: String? {
        model.selectedHostID.flatMap { id in model.connections.contains { $0["id"].string == id } ? id : nil }
    }
    private var hostNote: String? {
        if model.connections.isEmpty && model.devices.isEmpty { return String(localized: "mac.noDevices", bundle: .interface) }
        guard model.selectedHostID != nil else { return nil }
        return String(localized: savedHostID != nil ? "mac.connected" : "mac.nearby", bundle: .interface)
    }
    /// Saved and nearby entries carry distinct tags because a saved host can also be advertised nearby.
    private var hostSelection: Binding<String?> {
        Binding(get: {
            guard let id = model.selectedHostID else { return nil }
            return savedHostID != nil ? "saved:" + id : "nearby:" + id
        }, set: { tag in
            guard let tag, !model.busy else { return }
            workspaceID = nil
            if tag.hasPrefix("saved:") { let id = String(tag.dropFirst(6)); Task { await model.open(hostID: id) } }
            else if let device = model.devices.first(where: { "nearby:" + $0.host.id == tag }) { Task { await model.select(device) } }
        })
    }
    private var workspaceItems: [MacTableItem] {
        model.workspaces.compactMap { workspace in
            workspace["id"].string.map { MacTableItem(id: $0, title: workspace["title"].string ?? String(localized: "mac.untitled", bundle: .interface)) }
        }
    }
    private var workspaceSelection: Binding<String?> {
        Binding(get: { workspaceItems.first { $0.id == workspaceID }?.id ?? workspaceItems.first?.id }, set: { workspaceID = $0 })
    }
}
