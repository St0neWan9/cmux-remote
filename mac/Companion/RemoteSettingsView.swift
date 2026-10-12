import SwiftUI
import AppKit

struct RemoteSettingsView: View {
    @Bindable var app: MacAppModel
    let sectionChanged: () -> Void
    private let design = MacDesignTokens()
    var body: some View {
        VStack(spacing: 0) {
            if let code = app.serviceError {
                MacSettingsRow(title: String(localized: "mac.setup.title")) {
                    Label(MacErrorPresentation.message(code), systemImage: "exclamationmark.circle").font(.callout)
                    Text(String(localized: "mac.setup.instructions")).font(.caption).foregroundStyle(.secondary)
                    Text(app.setupCommand).font(.caption.monospaced()).textSelection(.enabled)
                    HStack {
                        Button(String(localized: "mac.setup.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.setupCommand, forType: .string) }
                        Button(String(localized: "mac.setup.retry")) { Task { await app.reconnect() } }.disabled(app.starting)
                    }
                }.padding(design.pagePadding)
            }
            if app.section == "share" { SharingSettingsView(model: app.sharing) }
            else { CompanionView(model: app.remote) }
            Divider()
            if app.section == "share" {
                MacSettingsRow(title: "") { advanced }
                    .frame(maxWidth: design.contentWidth).padding(.horizontal, design.pagePadding).padding(.vertical, 14).frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 0) {
                    Color.clear.frame(width: design.sidebarWidth)
                    advanced.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, design.pagePadding)
                }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 14)
            }
        }.background(Color(nsColor: MacPreferenceAppearance.background))
            .font(.system(size: 13)).controlSize(.regular)
            .frame(minWidth: 680, minHeight: 360)
            .onChange(of: app.section) { sectionChanged() }
    }
    private var advanced: some View {
        MacDetailsDisclosure(title: String(localized: "mac.advanced")) {
            Text(String(localized: "mac.stateDirectory")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(String(localized: "mac.stateDirectory"), text: $app.statePath).textFieldStyle(.roundedBorder)
                Button(String(localized: "mac.apply")) { Task { await app.applyStatePath() } }.disabled(app.starting).fixedSize()
            }
        }
    }

}
