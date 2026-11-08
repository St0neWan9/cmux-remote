import SwiftUI

/// The app's own page: which build is running, where it comes from and where it is documented.
struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
    private let website = URL(string: "https://cmux-remote.trenta.dev")!
    private let source = URL(string: "https://github.com/St0neWan9/cmux-remote")!
    var body: some View {
        MacPreferencePage {
            MacPreferenceRow(title: String(localized: "mac.title", bundle: .interface)) {
                Text(verbatim: "Cmux Remote \(version)")
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mac.about.version")
                MacPreferenceNote(text: String(localized: "mac.about.note", bundle: .interface))
            }
            MacPreferenceRow(title: String(localized: "mac.about.website", bundle: .interface)) {
                Link("cmux-remote.trenta.dev", destination: website)
                    .accessibilityIdentifier("mac.about.website")
            }
            MacPreferenceRow(title: String(localized: "mac.about.source", bundle: .interface)) {
                Link("github.com/St0neWan9/cmux-remote", destination: source)
                    .accessibilityIdentifier("mac.about.source")
            }
        }
    }
}
