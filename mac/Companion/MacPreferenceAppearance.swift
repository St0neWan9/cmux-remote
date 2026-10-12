import AppKit

/// Classic preference-window tones from the supplied reference; controls remain system drawn.
struct MacPreferenceAppearance {
    static let background = NSColor(name: "CmuxRemotePreferences") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 1)
            : NSColor(white: 0.9255, alpha: 1)
    }
}
