import SwiftUI
import CmuxRemoteMac

/// Native discovery, explicit first-use trust, owner approval, and mirror selection.
struct CompanionView: View {
    @Bindable var model: MacCompanionModel
    var body: some View {
        NavigationSplitView {
            List {
                if !model.connections.isEmpty {
                    Section(String(localized: "mac.connected")) {
                        ForEach(Array(model.connections.enumerated()), id: \.offset) { _, connection in
                            Button {
                                if let id = connection["id"].string { Task { await model.open(hostID: id) } }
                            } label: {
                                Label(connection["name"].string ?? String(localized: "mac.untitled"), systemImage: "checkmark.shield")
                            }.disabled(model.busy)
                            .contextMenu {
                                Button(String(localized: "mac.forgetHost")) {
                                    if let id = connection["id"].string { Task { await model.forget(hostID: id) } }
                                }.disabled(model.busy)
                            }
                            .help(String(localized: "mac.forgetHint"))
                        }
                    }
                }
                Section(String(localized: "mac.nearby")) {
                    ForEach(model.devices) { device in
                        Button { Task { await model.select(device) } } label: {
                            Label(device.host.name, systemImage: "desktopcomputer")
                        }.disabled(model.busy)
                    }
                    if model.devices.isEmpty { Text(String(localized: "mac.noDevices")).foregroundStyle(.secondary) }
                }
            }.navigationTitle(String(localized: "mac.title"))
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "mac.workspaces")).font(.title2)
                if model.pendingRequestID != nil {
                    Text(String(localized: "mac.awaitApproval"))
                    if let id = model.pendingRequestID { Text(id).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    Button(String(localized: "mac.cancel")) { Task { await model.cancelEnrollment() } }
                }
                if model.busy { ProgressView() }
                if let code = model.mirrorErrorCode ?? model.errorCode {
                    Text(MacErrorPresentation.message(code)).foregroundStyle(.red)
                    Text(String(localized: "mac.bridgeHint")).font(.caption).textSelection(.enabled)
                }
                List(Array(model.workspaces.enumerated()), id: \.offset) { _, workspace in
                    HStack {
                        Text(workspace["title"].string ?? String(localized: "mac.untitled"))
                        Spacer()
                        Button(String(localized: "mac.mirror")) {
                            if let id = workspace["id"].string { Task { await model.mirror(workspaceID: id) } }
                        }.disabled(model.busy)
                    }
                }
                Text(String(localized: "mac.snapshotNote")).font(.caption).foregroundStyle(.secondary)
                if model.mirroredWorkspaceID != nil { Label(String(localized: "mac.mirrored"), systemImage: "checkmark.circle") }
                Button(String(localized: "mac.refresh")) { Task { await model.refresh() } }
            }.padding()
        }
        .sheet(isPresented: Binding(get: { model.trustCandidate != nil }, set: { if !$0 { model.declineTrust() } })) {
            if let device = model.trustCandidate {
                HostTrustSheet(name: device.host.name, fingerprint: device.host.certificateSHA256,
                    confirm: { Task { await model.confirmTrust(device) } }, cancel: { model.declineTrust() })
            }
        }
    }
}
