import SwiftUI
import AppKit

/// First-use cmux connection guidance; it never types into a terminal or changes socket policy.
struct MacSetupRows: View {
    let app: MacAppModel
    var body: some View {
        if let code = app.serviceError {
            MacPreferenceRow(title: String(localized: "mac.setup.title", bundle: .interface)) {
                Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                MacPreferenceNote(text: String(localized: "mac.setup.instructions", bundle: .interface))
                Text(app.setupCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(String(localized: "mac.setup.copy", bundle: .interface)) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.setupCommand, forType: .string)
                    }.fixedSize()
                    Button(String(localized: "mac.setup.retry", bundle: .interface)) { Task { await app.reconnect() } }.disabled(app.starting).fixedSize()
                    if app.starting { ProgressView().controlSize(.small) }
                }
            }
        }
    }
}
