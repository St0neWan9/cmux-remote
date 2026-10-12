import AppKit

/// The system preference toolbar owns category icons, labels and selection rendering.
@MainActor final class RemoteSettingsToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "CmuxRemoteSettings")
    private let model: MacAppModel
    private let share = NSToolbarItem.Identifier("share")
    private let connect = NSToolbarItem.Identifier("connect")
    init(model: MacAppModel) {
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        updateSelection()
    }
    func updateSelection() { toolbar.selectedItemIdentifier = model.section == "share" ? share : connect }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [share, connect] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [share, connect] }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [share, connect] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == share || identifier == connect else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: identifier == share ? "mac.share.title" : "mac.connect.title")
        item.paletteLabel = item.label
        item.image = NSImage(systemSymbolName: identifier == share ? "square.and.arrow.up" : "desktopcomputer", accessibilityDescription: item.label)
        item.image?.size = NSSize(width: 20, height: 20)
        item.target = self; item.action = #selector(selectSection(_:))
        return item
    }
    @objc private func selectSection(_ sender: NSToolbarItem) {
        model.section = sender.itemIdentifier == share ? "share" : "connect"
        updateSelection()
    }
}
