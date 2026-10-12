import SwiftUI

/// Describes the existing remote workspace and its local opening action.
struct RemoteWorkspaceRow: View {
    let title: String
    let open: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lineLimit(1).help(title).textSelection(.enabled)
                Text(String(localized: "mac.workspaceHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: open) {
                Label(String(localized: "mac.mirror"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}
