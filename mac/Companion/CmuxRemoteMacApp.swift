import AppKit

/// Native menu bar lifetime with SwiftUI settings content and one window owner.
@main @MainActor struct CmuxRemoteMacApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true ? .accessory : .regular)
        let delegate = RemoteAppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
