import SwiftUI
import CmuxRemoteMac
import CmuxRemoteCore

/// Exact-request approval and per-device revocation; actions apply only to the selected row.
struct DevicesSettingsView: View {
    @Bindable var model: MacSharingModel
    @State private var pendingID: String?
    @State private var clientID: String?
    @State private var showingRevoke = false
    private let design = MacDesignTokens()
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.devices.pending", bundle: .interface), topAligned: !model.pending.isEmpty) {
                if model.pending.isEmpty { Text(String(localized: "mac.devices.noPending", bundle: .interface)).foregroundStyle(.secondary) }
                else {
                    deviceTable(pendingItems, selection: selection($pendingID, in: pendingItems))
                    if let request = selectedRequest {
                        details(clientID: request.clientID, workspaces: request.scope.workspaces, capabilities: request.scope.capabilities)
                        HStack(spacing: 8) {
                            Button(String(localized: "mac.device.deny", bundle: .interface), role: .destructive) { Task { await model.deny(request) } }.fixedSize()
                            Button(String(localized: "mac.device.approve", bundle: .interface)) { Task { await model.approve(request) } }.fixedSize()
                        }.disabled(model.busy)
                    }
                }
            }
            MacPreferenceRow(title: String(localized: "mac.devices.authorized", bundle: .interface), topAligned: !model.clients.isEmpty) {
                if model.clients.isEmpty { Text(String(localized: "mac.devices.empty", bundle: .interface)).foregroundStyle(.secondary) }
                else {
                    deviceTable(clientItems, selection: selection($clientID, in: clientItems))
                    if let client = selectedClient {
                        details(clientID: client["id"].string ?? "",
                                workspaces: (client["scope"]["workspaces"].array ?? []).compactMap(\.string),
                                capabilities: (client["scope"]["capabilities"].array ?? []).compactMap { $0.string.flatMap(ClientCapability.init(rawValue:)) })
                        Button(String(localized: "mac.device.revoke", bundle: .interface), role: .destructive) { showingRevoke = true }.fixedSize().disabled(model.busy)
                    }
                }
            }
        }
        .confirmationDialog(String(localized: "mac.device.revokeConfirm", bundle: .interface), isPresented: $showingRevoke, titleVisibility: .visible) {
            Button(String(localized: "mac.device.revoke", bundle: .interface), role: .destructive) {
                if let id = selectedClient?["id"].string { Task { await model.revoke(clientID: id) } }
            }
            Button(String(localized: "mac.cancel", bundle: .interface), role: .cancel) {}
        } message: {
            Text(selectedClient?["name"].string ?? selectedClient?["id"].string ?? "")
        }
    }
    private func deviceTable(_ items: [MacTableItem], selection: Binding<String?>) -> some View {
        Table(items, selection: selection) {
            TableColumn(String(localized: "mac.column.device", bundle: .interface)) { item in
                Label(item.title, systemImage: item.symbol ?? "desktopcomputer").lineLimit(1).help(item.title)
            }
            TableColumn(String(localized: "mac.column.identity", bundle: .interface)) { item in Text(item.detail).font(.body.monospaced()) }.width(120)
        }.tableStyle(.bordered(alternatesRowBackgrounds: true)).frame(height: design.tableHeight)
    }
    /// The complete identity and scope stay visible for the selected device; the short ID never replaces it.
    private func details(clientID: String, workspaces: [String], capabilities: [ClientCapability]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MacPreferenceNote(text: workspaces.map(workspaceName).joined(separator: ", "))
            MacPreferenceNote(text: capabilities.map { MacCapabilityPresentation().name($0) }.joined(separator: ", "))
            Text(clientID).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
        }
    }
    /// A missing or stale selection shows the first row, so every action names a visible device.
    private func selection(_ state: Binding<String?>, in items: [MacTableItem]) -> Binding<String?> {
        Binding(get: { items.first { $0.id == state.wrappedValue }?.id ?? items.first?.id }, set: { state.wrappedValue = $0 })
    }
    private var pendingItems: [MacTableItem] {
        model.pending.map { MacTableItem(id: $0.requestID, title: $0.clientName, detail: String($0.clientID.uppercased().prefix(12)),
                                         symbol: $0.clientKind == "iphone" ? "iphone" : "desktopcomputer") }
    }
    private var clientItems: [MacTableItem] {
        model.clients.compactMap { client in
            client["id"].string.map { MacTableItem(id: $0, title: client["name"].string ?? $0, detail: String($0.uppercased().prefix(12)),
                                                   symbol: client["kind"].string == "iphone" ? "iphone" : "desktopcomputer") }
        }
    }
    private var selectedRequest: EnrollmentRequest? {
        let id = selection($pendingID, in: pendingItems).wrappedValue
        return model.pending.first { $0.requestID == id }
    }
    private var selectedClient: JSONValue? {
        let id = selection($clientID, in: clientItems).wrappedValue
        return model.clients.first { $0["id"].string == id }
    }
    private func workspaceName(_ id: String) -> String {
        model.workspaces.first { $0["id"].string?.lowercased() == id.lowercased() }?["title"].string ?? id
    }
}
