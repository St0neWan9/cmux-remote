import AppKit

/// The system preference toolbar owns category icons, labels and selection rendering.
@MainActor final class RemoteSettingsToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "CmuxRemoteSettings")
    private let model: MacAppModel
    /// Section identifier, label key and symbol, in toolbar order.
    private let sections: [(id: String, label: String, symbol: String)] = [
        ("share", "mac.share.title", "square.and.arrow.up"),
        ("pairing", "mac.pairing.title", "qrcode"),
        ("devices", "mac.devices.title", "laptopcomputer.and.iphone"),
        ("connect", "mac.connect.title", "desktopcomputer"),
        ("advanced", "mac.advanced.title", "gearshape.2"),
    ]
    private var identifiers: [NSToolbarItem.Identifier] { sections.map { NSToolbarItem.Identifier($0.id) } }
    init(model: MacAppModel) {
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        updateSelection()
    }
    /// Labels follow the selected interface language without recreating the toolbar.
    func refreshLabels() {
        for item in toolbar.items {
            guard let section = sections.first(where: { $0.id == item.itemIdentifier.rawValue }) else { continue }
            item.label = String(localized: String.LocalizationValue(section.label), bundle: .interface); item.paletteLabel = item.label
        }
    }
    func updateSelection() { toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(model.section) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = sections.first(where: { $0.id == identifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: String.LocalizationValue(section.label), bundle: .interface)
        item.paletteLabel = item.label
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: item.label)
        item.target = self; item.action = #selector(selectSection(_:))
        return item
    }
    @objc private func selectSection(_ sender: NSToolbarItem) {
        model.section = sender.itemIdentifier.rawValue
        updateSelection()
    }
}
