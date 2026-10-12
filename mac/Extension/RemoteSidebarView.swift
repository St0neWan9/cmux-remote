import SwiftUI
import CmuxRemoteMac

/// Public metadata plus system navigation to the containing app; no secret-bearing URLs.
struct RemoteSidebarView: View {
    var model: RemoteSidebarModel
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                Button(String(localized: "mac.openCompanion")) { openURL(MacNavigationRequest.url()) }
                Text(String(localized: "mac.extensionHint")).font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "mac.localWorkspaces")) {
                ForEach(model.context?.snapshot.workspaces ?? []) { workspace in
                    Button { Task { await model.selectWorkspace(workspace.id) } } label: {
                        Label(workspace.title, systemImage: "rectangle.split.2x1")
                    }
                }
            }
            if let code = model.errorCode { Text(MacErrorPresentation.message(code)).foregroundStyle(.red) }
        }.listStyle(.sidebar)
    }
}
