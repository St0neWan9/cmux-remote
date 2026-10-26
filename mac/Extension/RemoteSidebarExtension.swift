import SwiftUI
import CmuxExtensionKit
import CmuxRemoteClient

/// Public cmux sidebar extension; uses no internal host SPI or native mirror provider.
@main @MainActor final class RemoteSidebarExtension: CmuxSidebarExtension {
    static let manifest = CmuxExtensionManifest(id: Bundle.main.bundleIdentifier ?? "cmux-remote.desktop.sidebar",
        displayName: String(localized: "mac.title"), readScopes: [.workspaceList, .workspaceMetadata], actionScopes: [.selectWorkspace])
    private let model = RemoteSidebarModel()
    required init() {}
    var body: some View { RemoteSidebarView(model: model) }
    func update(context: CmuxSidebarContext) { model.update(context) }
}
