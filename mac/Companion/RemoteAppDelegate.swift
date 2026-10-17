import AppKit
import SwiftUI
import CmuxRemoteMac

/// Owns one settings window; menu status labels do not own application lifetime.
@MainActor final class RemoteAppDelegate: NSObject, NSApplicationDelegate {
    let model: MacAppModel
    private var settingsWindow: NSWindow?
    private var settingsToolbar: RemoteSettingsToolbar?
    private var logWindow: NSWindow?
    private var logOcclusion: (any NSObjectProtocol)?
    private var statusItem: NSStatusItem?
    private var statusMenu: RemoteStatusMenu?
    private var applicationMenu: RemoteStatusMenu?
    override init() {
        model = MacAppModel(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cmux-remote"), home: FileManager.default.homeDirectoryForCurrentUser, preferences: .standard)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = RemoteStatusMenu(model: model, openSettings: { [weak self] in self?.showSettings() }, languageChanged: { [weak self] in self?.applyLanguage() })
        statusMenu = menu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.connected.to.line.below", accessibilityDescription: String(localized: "mac.menu.accessibility", bundle: .interface))
        item.menu = menu.menu; statusItem = item
        installMainMenu()
        Task {
            await model.start()
            // A silent launch shows only the menu bar icon; the acceptance fixture still needs its window.
            if !model.launch.silentLaunch || acceptanceOpenSettings { showSettings() }
        }
    }
    private func installMainMenu() {
        let main = NSMenu(title: String(localized: "mac.title", bundle: .interface))
        let appItem = NSMenuItem(title: String(localized: "mac.title", bundle: .interface), action: nil, keyEquivalent: ""); main.addItem(appItem)
        let appMenu = RemoteStatusMenu(model: model, openSettings: { [weak self] in self?.showSettings() }, languageChanged: { [weak self] in self?.applyLanguage() })
        applicationMenu = appMenu; appItem.submenu = appMenu.menu
        let fileItem = NSMenuItem(title: String(localized: "mac.menu.file", bundle: .interface), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: fileItem.title)
        fileMenu.addItem(NSMenuItem(title: String(localized: "mac.menu.closeWindow", bundle: .interface), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu; main.addItem(fileItem)
        // Text fields copy, paste and undo only through a standard Edit menu in the responder chain.
        main.addItem(editMenuItem())
        NSApplication.shared.mainMenu = main
    }
    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "mac.menu.edit", bundle: .interface), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: item.title)
        // NSStandardKeyBindingResponding actions live on NSText in Swift; undo and redo have no
        // typed declaration, so their selectors stay literal.
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.undo", bundle: .interface), action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.redo", bundle: .interface), action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.cut", bundle: .interface), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.copy", bundle: .interface), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.paste", bundle: .interface), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: String(localized: "mac.menu.selectAll", bundle: .interface), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        item.submenu = menu
        return item
    }
    /// Menus, toolbar and window title switch immediately; SwiftUI pages rebuild from the model's language.
    private func applyLanguage() {
        installMainMenu()
        statusItem?.button?.image?.accessibilityDescription = String(localized: "mac.menu.accessibility", bundle: .interface)
        settingsWindow?.title = String(localized: "mac.settings.title", bundle: .interface)
        settingsToolbar?.refreshLabels()
        logWindow?.title = String(localized: "mac.logs.windowTitle", bundle: .interface)
        (logWindow?.contentView as? NSHostingView<MacLogView>)?.rootView = MacLogView(model: model.logs, language: model.language)
    }
    @objc private func openSettingsFromMenu() { showSettings() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettingsFromMenu(); return false }
    func showSettings() {
        if settingsWindow == nil {
            // Like a classic preference window, the frame is not user-resizable; it follows each page's fitted size.
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = String(localized: "mac.settings.title", bundle: .interface); window.isReleasedWhenClosed = false
            let toolbar = RemoteSettingsToolbar(model: model)
            settingsToolbar = toolbar; window.toolbar = toolbar.toolbar; window.toolbarStyle = .preference
            let content = NSHostingView(rootView: RemoteSettingsView(app: model, sectionChanged: { [weak toolbar] in toolbar?.updateSelection() }, openLogs: { [weak self] in self?.showLogs() }))
            window.contentView = content; window.setContentSize(content.fittingSize)
            window.center(); settingsWindow = window
        }
        settingsToolbar?.updateSelection()
        NSApplication.shared.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
        // Preference panes open without a focused field, so no control shows a focus ring until used.
        settingsWindow?.makeFirstResponder(nil)
    }
    /// One reusable, resizable log window; it reads the log only while it is on screen.
    func showLogs() {
        if logWindow == nil {
            let design = MacDesignTokens()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: design.logWindowWidth, height: design.logWindowHeight),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = String(localized: "mac.logs.windowTitle", bundle: .interface); window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: design.logMinimumWidth, height: design.logMinimumHeight)
            window.contentView = NSHostingView(rootView: MacLogView(model: model.logs, language: model.language))
            window.setFrameAutosaveName("CmuxRemoteBridgeLog")
            if window.frame.origin == .zero { window.center() }
            // Closing, miniaturizing or covering the window stops the periodic read; showing it again resumes.
            logOcclusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated { self?.model.logs.windowVisible = window?.occlusionState.contains(.visible) == true }
            }
            logWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true); logWindow?.makeKeyAndOrderFront(nil)
        model.logs.windowVisible = true
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
