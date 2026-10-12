import SwiftUI
import CmuxRemoteMac

/// Two fixed alignment columns; terminal work remains in the native cmux workspace.
struct CompanionView: View {
    @Bindable var model: MacCompanionModel
    private let design = MacDesignTokens()
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.connections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("mac.connected")
                            ForEach(Array(model.connections.enumerated()), id: \.offset) { _, connection in
                                deviceRow(name: connection["name"].string ?? String(localized: "mac.untitled"), selected: connection["id"].string == model.selectedHostID, symbol: "checkmark.shield") {
                                    if let id = connection["id"].string { Task { await model.open(hostID: id) } }
                                }.contextMenu {
                                    Button(String(localized: "mac.forgetHost")) {
                                        if let id = connection["id"].string { Task { await model.forget(hostID: id) } }
                                    }.disabled(model.busy)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("mac.nearby")
                        ForEach(model.devices) { device in
                            deviceRow(name: device.host.name, selected: device.host.id == model.selectedHostID, symbol: "desktopcomputer") {
                                Task { await model.select(device) }
                            }
                        }
                        if model.devices.isEmpty { Text(String(localized: "mac.noDevices")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10) }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 24)
            }.frame(width: design.sidebarWidth)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: design.groupSpacing) {
                    Text(selectedHostName ?? String(localized: "mac.workspaces")).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(selectedHostName ?? "")
                    if model.pendingRequestID != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(String(localized: "mac.awaitApproval"), systemImage: "clock").font(.callout)
                            if let id = model.pendingRequestID { Text(id).font(.caption.monospaced()).textSelection(.enabled) }
                            Button(String(localized: "mac.cancel")) { Task { await model.cancelEnrollment() } }.fixedSize()
                        }
                    }
                    if let code = model.mirrorErrorCode ?? model.errorCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                            Text(String(localized: "mac.bridgeHint")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.selectedHostID == nil {
                        Text(String(localized: "mac.selectHost")).font(.callout).foregroundStyle(.secondary)
                    } else if !model.workspaces.isEmpty {
                        Text(String(localized: "mac.workspaces")).font(.callout)
                        List(Array(model.workspaces.enumerated()), id: \.offset) { _, workspace in
                            HStack(spacing: 12) {
                                Text(workspace["title"].string ?? String(localized: "mac.untitled")).lineLimit(1).help(workspace["title"].string ?? "")
                                Spacer(minLength: 12)
                                Button(String(localized: "mac.mirror")) {
                                    if let id = workspace["id"].string { Task { await model.mirror(workspaceID: id) } }
                                }.fixedSize().disabled(model.busy)
                            }.frame(minHeight: 28)
                        }.listStyle(.bordered).frame(height: max(88, min(240, CGFloat(model.workspaces.count) * 40 + 12)))
                        if model.mirroredWorkspaceID != nil {
                            Label(String(localized: "mac.mirrored"), systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                        }
                        Text(String(localized: "mac.snapshotNote")).font(.caption).foregroundStyle(.secondary)
                    } else if !model.busy && model.pendingRequestID == nil && model.errorCode == nil {
                        Text(String(localized: "mac.workspaces.empty")).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(String(localized: "mac.refresh")) { Task { await model.refresh() } }.disabled(model.busy)
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(design.pagePadding)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: Binding(get: { model.trustCandidate != nil }, set: { if !$0 { model.declineTrust() } })) {
            if let device = model.trustCandidate {
                HostTrustSheet(name: device.host.name, fingerprint: device.host.certificateSHA256,
                    confirm: { Task { await model.confirmTrust(device) } }, cancel: { model.declineTrust() })
            }
        }
    }
    private var selectedHostName: String? {
        model.connections.first { $0["id"].string == model.selectedHostID }?["name"].string
            ?? model.devices.first { $0.host.id == model.selectedHostID }?.host.name
    }
    private func sectionTitle(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key))).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
    }
    private func deviceRow(name: String, selected: Bool, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 36).frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(name).disabled(model.busy)
    }
}
