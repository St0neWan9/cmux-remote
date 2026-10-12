import AppKit

/// Native menus share the same settings window and owner-side model actions.
@MainActor final class RemoteStatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: String(localized: "mac.title", bundle: .interface))
    private let model: MacAppModel
    private let openSettings: () -> Void
    private let languageChanged: () -> Void
    init(model: MacAppModel, openSettings: @escaping () -> Void, languageChanged: @escaping () -> Void) {
        self.model = model; self.openSettings = openSettings; self.languageChanged = languageChanged
        super.init(); menu.delegate = self; menu.autoenablesItems = false
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: String(localized: model.sharing.isSharing ? "mac.share.running" : "mac.share.stopped", bundle: .interface), action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status)
        if !model.sharing.pending.isEmpty {
            let pending = NSMenuItem(title: String(format: String(localized: "mac.menu.pending", bundle: .interface), model.sharing.pending.count), action: #selector(showPending), keyEquivalent: "")
            pending.target = self; menu.addItem(pending)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "mac.menu.settings", bundle: .interface), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let language = NSMenuItem(title: String(localized: "mac.menu.language", bundle: .interface), action: nil, keyEquivalent: "")
        let choices = NSMenu(title: language.title)
        for option in MacInterfaceLanguage.allCases {
            let choice = NSMenuItem(title: option.displayName, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            choice.target = self; choice.representedObject = option.rawValue; choice.state = option == model.language ? .on : .off
            choices.addItem(choice)
        }
        language.submenu = choices; menu.addItem(language)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "mac.menu.quit", bundle: .interface), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
    }
    @objc private func showSettings() { openSettings() }
    @objc private func showPending() { model.section = "devices"; openSettings() }
    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = MacInterfaceLanguage(rawValue: raw), language != model.language else { return }
        model.language = language; languageChanged()
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
