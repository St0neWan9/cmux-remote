import SwiftUI
import AVFAudio

@main
struct CmuxRemoteApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var model: AppModel
    init() {
        let speechFactory: @MainActor () -> any SpeechInputServing = {
            SpeechInputService(audio: AVAudioSession.sharedInstance(), locale: .current)
        }
        _model = State(initialValue: AppModel(makeSpeechInput: speechFactory))
    }
    var body: some Scene {
        WindowGroup {
            Group {
                // Approved Macs open straight into the combined conversation list.
                if model.links.isEmpty || model.addingDevice { PairingView(model: model) }
                else { SessionListView(model: model) }
            }.environment(\.colorScheme, .light).tint(MobileDesign.accent).task(id: phase) {
                model.restorePairing()
                if phase == .active { model.resumeEnrollment(); await model.discover() }
                else { model.pauseEnrollment() }
            }
        }
    }
}
