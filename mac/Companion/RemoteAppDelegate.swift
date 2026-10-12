import AppKit
import SwiftUI
import CmuxRemoteMac

/// Owns one settings window; menu status labels do not own application lifetime.
@MainActor final class RemoteAppDelegate: NSObject, NSApplicationDelegate {
    let model: MacAppModel
    private var settingsWindow: NSWindow?
    private var settingsToolbar: RemoteSettingsToolbar?
    private var statusItem: NSStatusItem?
    private var statusMenu: RemoteStatusMenu?
    private var applicationMenu: RemoteStatusMenu?
    override init() {
        model = MacAppModel(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cmux-remote"), home: FileManager.default.homeDirectoryForCurrentUser, preferences: .standard)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = RemoteStatusMenu(model: model, openSettings: { [weak self] in self?.showSettings() })
        statusMenu = menu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.connected.to.line.below", accessibilityDescription: String(localized: "mac.menu.accessibility"))
        item.menu = menu.menu; statusItem = item
        let main = NSMenu(title: String(localized: "mac.title"))
        let appItem = NSMenuItem(title: String(localized: "mac.title"), action: nil, keyEquivalent: ""); main.addItem(appItem)
        let appMenu = RemoteStatusMenu(model: model, openSettings: { [weak self] in self?.showSettings() })
        applicationMenu = appMenu; appItem.submenu = appMenu.menu
        let fileItem = NSMenuItem(title: String(localized: "mac.menu.file"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: fileItem.title)
        fileMenu.addItem(NSMenuItem(title: String(localized: "mac.menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu; main.addItem(fileItem)
        NSApplication.shared.mainMenu = main
        Task {
            await model.start()
            if model.serviceError != nil || acceptanceOpenSettings { showSettings() }
        }
    }
    @objc private func openSettingsFromMenu() { showSettings() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettingsFromMenu(); return false }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 452), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = String(localized: "mac.settings.title"); window.isReleasedWhenClosed = false
            let toolbar = RemoteSettingsToolbar(model: model)
            settingsToolbar = toolbar; window.toolbar = toolbar.toolbar; window.toolbarStyle = .preference
            window.contentView = NSHostingView(rootView: RemoteSettingsView(app: model, sectionChanged: { [weak toolbar] in toolbar?.updateSelection() }))
            window.backgroundColor = MacPreferenceAppearance.background; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 700, height: 480)
            window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 540), display: false)
            window.center(); settingsWindow = window
        }
        settingsToolbar?.updateSelection()
        NSApplication.shared.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    /// A task-owned debug fixture obtains a stable capture handle before exercising the real UI.
    private var acceptanceOpenSettings: Bool {
        #if DEBUG
        Bundle.main.object(forInfoDictionaryKey: "CmuxRemoteAcceptanceOpenSettings") as? Bool == true
        #else
        false
        #endif
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, let request = try? MacNavigationRequest(url: url) else { return }
        model.section = "connect"; showSettings()
        Task { await model.start(); if let id = request.hostID { await model.remote.open(hostID: id) } }
    }
    func applicationWillTerminate(_ notification: Notification) { model.sharing.stopObservation(); model.remote.stop() }
}
