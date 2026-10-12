import SwiftUI
import AVFAudio

@main
struct CmuxRemoteApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var model = AppModel(makeSpeechInput: { SpeechInputService(audio: AVAudioSession.sharedInstance(), locale: .current) })
    var body: some Scene {
        WindowGroup {
            Group {
                if model.client == nil { PairingView(model: model) }
                else { SessionListView(model: model) }
            }.environment(\.colorScheme, .light).task(id: phase) {
                model.restorePairing()
                if phase == .active { model.resumeEnrollment(); await model.discover() }
                else { model.pauseEnrollment() }
            }
        }
    }
}
