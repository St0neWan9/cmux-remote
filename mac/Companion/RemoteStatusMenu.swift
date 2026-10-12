import AppKit

/// Native menus share the same settings window and owner-side model actions.
@MainActor final class RemoteStatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: String(localized: "mac.title"))
    private let model: MacAppModel
    private let openSettings: () -> Void
    init(model: MacAppModel, openSettings: @escaping () -> Void) {
        self.model = model; self.openSettings = openSettings
        super.init(); menu.delegate = self; menu.autoenablesItems = false
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: String(localized: model.sharing.isSharing ? "mac.share.running" : "mac.share.stopped"), action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status)
        if !model.sharing.pending.isEmpty {
            let pending = NSMenuItem(title: String(format: String(localized: "mac.menu.pending"), model.sharing.pending.count), action: #selector(showPending), keyEquivalent: "")
            pending.target = self; menu.addItem(pending)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "mac.menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "mac.menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
    }
    @objc private func showSettings() { openSettings() }
    @objc private func showPending() { model.section = "share"; openSettings() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
