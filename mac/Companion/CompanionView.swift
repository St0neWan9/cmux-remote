import SwiftUI
import CmuxRemoteMac
import CmuxRemoteClient

/// Two fixed alignment columns; terminal work remains in the native cmux workspace.
struct CompanionView: View {
    @Bindable var model: MacCompanionModel
    private let design = MacDesignTokens()
    private var savedHostIDs: Set<String> { Set(model.connections.compactMap { $0["id"].string }) }
    private var unpairedHosts: [DiscoveredBridge] { model.devices.filter { !savedHostIDs.contains($0.host.id) } }
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.connections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("mac.connected")
                            ForEach(Array(model.connections.enumerated()), id: \.offset) { _, connection in
                                HostConnectionRow(name: connection["name"].string ?? String(localized: "mac.unnamedHost"),
                                    subtitle: model.devices.contains { $0.host.id == connection["id"].string }
                                        ? String(localized: "mac.savedNearby") : String(localized: "mac.savedNotDiscovered"),
                                    systemImage: "checkmark.shield", selected: connection["id"].string == model.selectedHostID) {
                                    if let id = connection["id"].string { Task { await model.open(hostID: id) } }
                                }.disabled(model.busy).contextMenu {
                                    Button(String(localized: "mac.forgetHost")) {
                                        if let id = connection["id"].string { Task { await model.forget(hostID: id) } }
                                    }.disabled(model.busy)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("mac.nearby")
                        ForEach(unpairedHosts) { device in
                            HostConnectionRow(name: device.host.name, subtitle: String(localized: "mac.needsPairing"),
                                systemImage: "desktopcomputer", selected: device.host.id == model.selectedHostID) {
                                Task { await model.select(device) }
                            }.disabled(model.busy)
                        }
                        if unpairedHosts.isEmpty { Text(String(localized: "mac.noDevices")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10) }
                    }
                    Text(String(localized: "mac.hostListHint")).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 24)
            }.frame(width: design.sidebarWidth)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: design.groupSpacing) {
                    Text(selectedHostName ?? String(localized: "mac.workspaces")).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(selectedHostName ?? "")
                    Text(String(localized: "mac.workflowHint")).font(.caption).foregroundStyle(.secondary)
                    if model.pendingRequestID != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(String(localized: "mac.awaitApproval"), systemImage: "clock").font(.callout)
                            if let id = model.pendingRequestID { Text(id).font(.caption.monospaced()).textSelection(.enabled) }
                            Button(String(localized: "mac.cancel")) { Task { await model.cancelEnrollment() } }.fixedSize()
                        }
                    }
                    if let code = model.mirrorErrorCode ?? model.errorCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(MacErrorPresentation.message(code, forWorkspace: true), systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                            Text(String(localized: "mac.bridgeHint")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.selectedHostID == nil {
                        Text(String(localized: "mac.selectHostMessage")).font(.callout).foregroundStyle(.secondary)
                    } else if !model.workspaces.isEmpty {
                        Text(String(localized: "mac.workspaces")).font(.callout)
                        List(Array(model.workspaces.enumerated()), id: \.offset) { _, workspace in
                            RemoteWorkspaceRow(title: workspace["title"].string ?? String(localized: "mac.untitled")) {
                                if let id = workspace["id"].string { Task { await model.mirror(workspaceID: id) } }
                            }.disabled(model.busy)
                        }.listStyle(.bordered).frame(height: max(88, min(240, CGFloat(model.workspaces.count) * 56 + 12)))
                        if model.mirroredWorkspaceID != nil {
                            Label(String(localized: "mac.mirrored"), systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                        }
                        Text(String(localized: "mac.snapshotNote")).font(.caption).foregroundStyle(.secondary)
                    } else if !model.busy && model.pendingRequestID == nil && model.errorCode == nil {
                        Text(String(localized: "mac.noWorkspacesMessage")).font(.callout).foregroundStyle(.secondary)
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
}
