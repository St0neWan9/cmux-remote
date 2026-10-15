import SwiftUI
import CmuxRemoteClient

/// Which Mac's conversations the list shows, with each Mac's link state at a glance.
struct HostFilterTabs: View {
    struct Host: Identifiable { let id: String; let name: String; let state: LinkState?; let failed: Bool }
    let hosts: [Host]
    /// nil shows every Mac.
    @Binding var selection: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // With one Mac there is nothing to choose between; its tab only shows its state.
                if hosts.count > 1 { tab(id: nil, selected: selection == nil) { Text(String(localized: "sessions.all_hosts")) } }
                ForEach(hosts) { host in
                    tab(id: host.id, selected: hosts.count == 1 || selection == host.id) {
                        HStack(spacing: 7) {
                            Circle().fill(color(host)).frame(width: 7, height: 7)
                            Image(systemName: "laptopcomputer")
                            Text(host.name).lineLimit(1)
                        }
                    }
                }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("sessions.hosts")
    }
    private func tab(id: String?, selected: Bool, @ViewBuilder label: () -> some View) -> some View {
        Button { if hosts.count > 1 { selection = id } } label: {
            label().font(.subheadline.weight(selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(selected ? Color.black.opacity(0.05) : Color.clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("sessions.host." + (id ?? "all"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func color(_ host: Host) -> Color {
        if host.failed || host.state == .disconnected { return .red }
        return host.state == .connecting ? .orange : .green
    }
}
