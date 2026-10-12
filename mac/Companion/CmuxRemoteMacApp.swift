import SwiftUI
import AppKit
import CmuxRemoteMac
import CmuxRemoteClient
import CmuxRemoteBridge

/// Composition root for the independently installed containing app.
@main @MainActor struct CmuxRemoteMacApp: App {
    @State private var model: MacCompanionModel
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let state = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/cmux-remote")
        let owner = UnixSocketClient(path: state.appendingPathComponent("owner.sock").path)
        _model = State(initialValue: MacCompanionModel(owner: owner, discovery: OwnerBridgeDiscovery(owner: owner)))
    }
    var body: some Scene {
        WindowGroup(id: "companion") {
            CompanionView(model: model).frame(minWidth: 650, minHeight: 480)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
                .onOpenURL { url in
                    guard let request = try? MacNavigationRequest(url: url) else { return }
                    // An explicit sidebar open action should bring the one containing-app window forward.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let id = request.hostID { Task { await model.open(hostID: id) } }
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
    }
}
