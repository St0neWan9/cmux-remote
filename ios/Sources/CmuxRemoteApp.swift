import SwiftUI

@main
struct CmuxRemoteApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            Group {
                if model.client == nil { PairingView(model: model) }
                else { SessionListView(model: model) }
            }.task(id: phase) {
                model.restorePairing()
                if phase == .active { model.resumeEnrollment(); await model.discover() }
                else { model.pauseEnrollment() }
            }
        }
    }
}
