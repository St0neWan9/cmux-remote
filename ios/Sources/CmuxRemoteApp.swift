import SwiftUI

@main
struct CmuxRemoteApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            Group {
                if model.client == nil { PairingView(model: model) }
                else { SessionListView(model: model) }
            }.task { model.restorePairing() }
        }
    }
}
