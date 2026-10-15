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
                // Approval is required before any list exists; adding a further Mac is a push over that list.
                if model.links.isEmpty { PairingView(model: model) }
                else { SessionListView(model: model) }
            }.environment(\.colorScheme, .light).tint(MobileDesign.accent).task(id: phase) {
                model.restorePairing()
                if phase == .active { model.resumeEnrollment(); await model.discover() }
                else { model.pauseEnrollment(); if phase == .background { model.backgroundedAt = Date(); BackgroundSync.schedule() } }
            }
            // Restarted when a Mac is added or removed, so every link is followed.
            .task(id: ConnectionSupervision(active: phase == .active, hosts: model.links.map(\.id))) {
                guard phase == .active, !model.links.isEmpty else { return }
                await model.superviseConnections()
            }
            .task(id: ConnectionSupervision(active: phase == .active, hosts: model.links.map(\.id))) {
                guard phase == .active, !model.links.isEmpty else { return }
                await model.followSessions()
            }
        }
        // Woken by iOS while in the background; the next wake is asked for before this one reads anything.
        .backgroundTask(.appRefresh(BackgroundSync.identifier)) { [model] in
            await MainActor.run { BackgroundSync.schedule() }
            await model.syncInBackground()
        }
    }
}
