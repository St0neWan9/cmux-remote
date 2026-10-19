import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// Which Mac's conversations the list shows, with each Mac's link state at a glance, and under each Mac's
/// arrow the workspaces it shares. A Mac being dialed turns, and one that cannot be reached shows a red dot;
/// a working link shows nothing. A pull on the list dials again, so there is nothing to tap.
struct HostFilterTabs: View {
    struct Host: Identifiable { let id: String; let name: String; let state: LinkState?; let failed: Bool
        /// Retried in the background, so its dials are not shown turning.
        var quiet = false
        let workspaces: [WorkspaceSummary] }
    let hosts: [Host]
    /// nil shows every Mac.
    @Binding var selection: String?
    /// nil shows every workspace.
    @Binding var workspaceID: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // With one Mac there is nothing to choose between; its tab shows its state and workspaces.
                if hosts.count > 1 {
                    Button { selection = nil; workspaceID = nil } label: { capsule(selected: selection == nil) { Text(String(localized: "sessions.all_hosts")) } }
                        .buttonStyle(.plain).accessibilityIdentifier("sessions.host.all").accessibilityAddTraits(selection == nil ? .isSelected : [])
                }
                ForEach(hosts) { host in hostTab(host) }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("sessions.hosts")
    }
    @ViewBuilder private func hostTab(_ host: Host) -> some View {
        let selected = hosts.count == 1 || selection == host.id
        let workspace = host.workspaces.first { $0.id == workspaceID }
        let label = HStack(spacing: 7) {
            indicator(host)
            Image(systemName: "laptopcomputer")
            Text(workspace.map { host.name + " · " + $0.title } ?? host.name).lineLimit(1)
            if host.workspaces.count > 1 { Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
        }.contentShape(Rectangle())
        if selected, host.workspaces.count > 1 {
            // The whole capsule opens the workspaces, so their menu starts at the capsule's leading edge.
            Menu {
                Picker(String(localized: "sessions.workspace_filter"), selection: Binding(
                    get: { workspace?.id },
                    set: { id in workspaceID = id; if hosts.count > 1 { selection = host.id } })) {
                    Text(String(localized: "sessions.all_workspaces")).tag(String?.none)
                    ForEach(host.workspaces) { workspace in Text(workspace.title).tag(String?.some(workspace.id)) }
                }.pickerStyle(.inline)
            } label: { capsule(selected: true) { label } }
                .tint(.primary).accessibilityIdentifier("sessions.host." + host.id + ".workspaces").accessibilityValue(statusText(host) ?? "")
                .accessibilityAddTraits(.isSelected)
        } else {
            // A Mac not yet shown is chosen first; its workspaces open from the capsule once it is.
            Button { if hosts.count > 1 { selection = host.id } } label: { capsule(selected: selected) { label } }
                .buttonStyle(.plain).accessibilityIdentifier("sessions.host." + host.id).accessibilityValue(statusText(host) ?? "").accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
    private func capsule(selected: Bool, @ViewBuilder label: () -> some View) -> some View {
        label().font(.subheadline.weight(selected ? .medium : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(selected ? Color.black.opacity(0.05) : Color.clear, in: Capsule())
    }
    private enum Status { case connecting, unreachable }
    private func status(_ host: Host) -> Status? {
        // Dialing wins over an earlier failure, so a pull is seen to start.
        if host.state == .connecting && !host.quiet { return .connecting }
        if host.failed || host.state == .disconnected || host.state == .connecting { return .unreachable }
        return nil
    }
    private func statusText(_ host: Host) -> String? {
        switch status(host) {
        case .connecting: String(localized: "connection.reconnecting")
        case .unreachable: String(localized: "connection.offline")
        case nil: nil
        }
    }
    @ViewBuilder private func indicator(_ host: Host) -> some View {
        switch status(host) {
        case .connecting: WorkingIndicator(size: 12).accessibilityHidden(true)
        case .unreachable: Circle().fill(Color.red).frame(width: 7, height: 7)
        case nil: EmptyView()
        }
    }
}
