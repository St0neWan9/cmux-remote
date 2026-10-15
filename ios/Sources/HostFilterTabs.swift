import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// Which Mac's conversations the list shows, with each Mac's link state at a glance, and under each Mac's
/// arrow the workspaces it shares.
struct HostFilterTabs: View {
    struct Host: Identifiable { let id: String; let name: String; let state: LinkState?; let failed: Bool; let workspaces: [WorkspaceSummary] }
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
    private func hostTab(_ host: Host) -> some View {
        let selected = hosts.count == 1 || selection == host.id
        let workspace = host.workspaces.first { $0.id == workspaceID }
        return capsule(selected: selected) {
            HStack(spacing: 7) {
                Button { if hosts.count > 1 { selection = host.id } } label: {
                    HStack(spacing: 7) {
                        Circle().fill(color(host)).frame(width: 7, height: 7)
                        Image(systemName: "laptopcomputer")
                        Text(workspace.map { host.name + " · " + $0.title } ?? host.name).lineLimit(1)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("sessions.host." + host.id).accessibilityAddTraits(selected ? .isSelected : [])
                if host.workspaces.count > 1 {
                    Menu {
                        Picker(String(localized: "sessions.workspace_filter"), selection: Binding(
                            get: { workspace?.id },
                            set: { id in workspaceID = id; if hosts.count > 1 { selection = host.id } })) {
                            Text(String(localized: "sessions.all_workspaces")).tag(String?.none)
                            ForEach(host.workspaces) { workspace in Text(workspace.title).tag(String?.some(workspace.id)) }
                        }.pickerStyle(.inline)
                    } label: {
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
                    }.tint(.primary).accessibilityLabel(String(localized: "sessions.workspace_filter"))
                        .accessibilityIdentifier("sessions.host." + host.id + ".workspaces")
                }
            }
        }
    }
    private func capsule(selected: Bool, @ViewBuilder label: () -> some View) -> some View {
        label().font(.subheadline.weight(selected ? .medium : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(selected ? Color.black.opacity(0.05) : Color.clear, in: Capsule())
    }
    private func color(_ host: Host) -> Color {
        if host.failed || host.state == .disconnected { return .red }
        return host.state == .connecting ? .orange : .green
    }
}
