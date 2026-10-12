import Foundation

/// The app's own interface language, independent of the system language list; English unless chosen.
enum MacInterfaceLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    static let preferenceKey = "interfaceLanguage"
    static var current: MacInterfaceLanguage {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(MacInterfaceLanguage.init(rawValue:)) ?? .english
    }
    /// Each language names itself, so the choice stays readable whichever language is active.
    var displayName: String { self == .english ? "English" : "简体中文" }
    var locale: Locale { Locale(identifier: rawValue) }
    var bundle: Bundle { Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main }
}

extension Bundle {
    /// Localized interface strings resolve against the selected language rather than the system list.
    static var interface: Bundle { MacInterfaceLanguage.current.bundle }
}
