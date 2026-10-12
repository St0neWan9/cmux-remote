import SwiftUI
import CmuxRemoteMac
import CmuxRemoteCore

struct SharingSettingsView: View {
    @Bindable var model: MacSharingModel
    @State private var revokeID: String?
    @State private var showingRevoke = false
    private let design = MacDesignTokens()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: design.groupSpacing) {
                sharingRow
                if !model.pending.isEmpty { pendingRow }
                pairingRow
                authorizedRow
            }.frame(maxWidth: design.contentWidth).padding(design.pagePadding).frame(maxWidth: .infinity)
        }.confirmationDialog(String(localized: "mac.device.revokeConfirm"), isPresented: $showingRevoke, titleVisibility: .visible) {
            Button(String(localized: "mac.device.revoke"), role: .destructive) { if let id = revokeID { Task { await model.revoke(clientID: id) } }; revokeID = nil }
            Button(String(localized: "mac.cancel"), role: .cancel) { revokeID = nil }
        } message: {
            Text(model.clients.first { $0["id"].string == revokeID }?["name"].string ?? revokeID ?? "")
        }
    }
    private var sharingRow: some View {
        MacSettingsRow(title: String(localized: "mac.share.label")) {
            Toggle(String(localized: "mac.share.enable"), isOn: Binding(get: { model.isSharing }, set: { enabled in Task { await model.setSharing(enabled) } }))
                .toggleStyle(.checkbox).lineLimit(1).disabled(model.busy)
            HStack(spacing: 8) {
                Label(String(localized: model.isSharing ? "mac.share.running" : "mac.share.stopped"), systemImage: model.isSharing ? "checkmark.circle.fill" : "circle")
                    .font(.caption).foregroundStyle(model.isSharing ? .green : .secondary)
                if model.busy { ProgressView().controlSize(.small) }
                Button(String(localized: "mac.refresh")) { Task { await model.refresh() } }.controlSize(.small).disabled(model.busy)
            }
            if let code = model.errorCode { Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
            MacDetailsDisclosure(title: String(localized: "mac.share.connectionDetails")) {
                HStack(spacing: 8) {
                    Text(String(localized: "mac.share.port"))
                    TextField("", value: $model.port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80).disabled(model.isSharing || model.busy)
                }
                if model.isSharing, let address = model.address {
                    Text("https://" + address + ":" + String(model.port)).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                }
                Text(model.status["certificate"].string ?? "").font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }
    private var pendingRow: some View {
        MacSettingsRow(title: String(localized: "mac.devices.pending")) {
            ForEach(model.pending, id: \.requestID) { request in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Label(request.clientName, systemImage: request.clientKind == "iphone" ? "iphone" : "desktopcomputer").lineLimit(1).help(request.clientName)
                        Spacer(minLength: 12)
                        Button(String(localized: "mac.device.deny"), role: .destructive) { Task { await model.deny(request) } }.fixedSize()
                        Button(String(localized: "mac.device.approve")) { Task { await model.approve(request) } }.fixedSize()
                    }.disabled(model.busy)
                    Text(request.scope.workspaces.map(workspaceName).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    Text(request.scope.capabilities.map { MacCapabilityPresentation().name($0) }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    Text(request.clientID.uppercased().prefix(12)).font(.caption.monospaced()).textSelection(.enabled)
                    MacDetailsDisclosure(title: String(localized: "mac.device.details")) {
                        Text(request.clientID).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }
    private var pairingRow: some View {
        MacSettingsRow(title: String(localized: "mac.pairing.title")) {
            if let link = model.qrLink {
                HStack(alignment: .center, spacing: 16) {
                    PairingQRCodeView(link: link)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "mac.pairing.scanHint")).font(.caption).foregroundStyle(.secondary)
                        Text(model.selectedWorkspaces.sorted().map(workspaceName).joined(separator: ", ")).font(.caption)
                        if let expiry = model.expiresAt {
                            Text(String(localized: "mac.pairing.expires") + " " + Date(timeIntervalSince1970: Double(expiry)).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Button(String(localized: "mac.pairing.close")) { Task { await model.closePairing() } }.disabled(model.busy).fixedSize()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                List {
                    ForEach(Array(model.workspaces.enumerated()), id: \.offset) { _, workspace in
                        if let id = workspace["id"].string?.lowercased() {
                            Toggle(workspace["title"].string ?? String(localized: "mac.untitled"), isOn: Binding(get: { model.selectedWorkspaces.contains(id) }, set: { if $0 { model.selectedWorkspaces.insert(id) } else { model.selectedWorkspaces.remove(id) } }))
                                .toggleStyle(.checkbox).lineLimit(1).disabled(model.busy)
                        }
                    }
                    if model.workspaces.isEmpty { Text(String(localized: "mac.share.noWorkspaces")).font(.callout).foregroundStyle(.secondary) }
                }.listStyle(.bordered).frame(height: min(104, max(44, CGFloat(model.workspaces.count) * 26 + 12)))
                Text(String(localized: "mac.pairing.workspaceHint")).font(.caption).foregroundStyle(.secondary)
                Button(String(localized: "mac.pairing.open")) { Task { await model.openPairing() } }
                    .disabled(!model.isSharing || model.selectedWorkspaces.isEmpty || model.busy).fixedSize()
            }
        }
    }
    private var authorizedRow: some View {
        MacSettingsRow(title: String(localized: "mac.devices.authorized")) {
            if model.clients.isEmpty { Text(String(localized: "mac.devices.empty")).foregroundStyle(.secondary) }
            else {
                List {
                    ForEach(Array(model.clients.enumerated()), id: \.offset) { _, client in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text(client["name"].string ?? "").lineLimit(1).help(client["name"].string ?? "")
                                Spacer(minLength: 12)
                                Button(String(localized: "mac.device.revoke"), role: .destructive) { revokeID = client["id"].string; showingRevoke = true }.fixedSize().disabled(model.busy)
                            }
                            Text(String((client["id"].string ?? "").uppercased().prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                            MacDetailsDisclosure(title: String(localized: "mac.device.details")) {
                                Text(client["id"].string ?? "").font(.caption.monospaced()).textSelection(.enabled)
                                Text((client["scope"]["workspaces"].array ?? []).compactMap(\.string).map(workspaceName).joined(separator: ", ")).font(.caption)
                                Text((client["scope"]["capabilities"].array ?? []).compactMap { $0.string.flatMap(ClientCapability.init(rawValue:)) }.map { MacCapabilityPresentation().name($0) }.joined(separator: ", ")).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }.listStyle(.bordered).frame(height: min(200, max(96, CGFloat(model.clients.count) * 96)))
            }
        }
    }
    private func workspaceName(_ id: String) -> String {
        model.workspaces.first { $0["id"].string?.lowercased() == id.lowercased() }?["title"].string ?? id
    }
}
