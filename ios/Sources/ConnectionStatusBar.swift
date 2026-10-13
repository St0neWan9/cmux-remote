import SwiftUI
import CmuxRemoteClient

/// A link that is not up is shown at the top of the page until it is: dialing turns, a failure offers a retry.
struct ConnectionStatusBar: View {
    let state: LinkState?
    /// The unreachable Mac, named when the phone has several.
    var hostName: String? = nil
    let retry: () -> Void
    var body: some View {
        Group {
            switch state {
            case .connecting:
                HStack(spacing: 10) {
                    WorkingIndicator(size: 14)
                    Text(String(localized: "connection.reconnecting")).font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).frame(height: 40)
                .background(Color.white, in: Capsule())
                .accessibilityElement(children: .combine).accessibilityIdentifier("connection.reconnecting")
            case .disconnected:
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    Text(hostName.map { String.localizedStringWithFormat(String(localized: "connection.offline_named"), $0) } ?? String(localized: "connection.offline"))
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                    Button(action: retry) { Text(String(localized: "connection.retry")).font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityIdentifier("connection.retry")
                }
                .padding(.leading, 16).padding(.trailing, 18).frame(height: 40)
                .background(Color.white, in: Capsule())
                .accessibilityElement(children: .contain).accessibilityIdentifier("connection.offline")
            case .connected, nil:
                EmptyView()
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}
