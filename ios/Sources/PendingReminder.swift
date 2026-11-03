import SwiftUI

/// A strip under the Mac tabs saying how many items wait for a reply; hidden when none do.
struct PendingReminder: View {
    let feed: PendingFeed
    /// Macs with something pending; several open a choice, one opens its list directly.
    let hosts: [(id: String, name: String, count: Int)]
    let open: (String) -> Void
    var body: some View {
        if feed.count > 0, !hosts.isEmpty {
            if hosts.count == 1, let only = hosts.first { Button { open(only.id) } label: { strip }.buttonStyle(.plain) }
            else {
                Menu {
                    ForEach(hosts, id: \.id) { host in Button("\(host.name) (\(host.count))") { open(host.id) } }
                } label: { strip }.buttonStyle(.plain)
            }
        }
    }
    private var strip: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge").foregroundStyle(MobileDesign.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "sessions.pending_count"), feed.count)).font(.subheadline.weight(.semibold))
                if let title = feed.firstTitle { Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.modifier(FloatingSurface())
            .accessibilityElement(children: .combine).accessibilityIdentifier("sessions.pending")
    }
}
