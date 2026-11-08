import SwiftUI

/// The app's own page: which build is running, where it comes from and where it is documented.
struct AboutView: View {
    /// Marketing version and build, as this build carries them.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
    private let website = URL(string: "https://cmux-remote.trenta.dev")!
    private let source = URL(string: "https://github.com/St0neWan9/cmux-remote")!
    var body: some View {
        WhitePage(title: String(localized: "about.title"), dismissal: .back) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Cmux Remote").font(.title2.weight(.semibold))
                    Text(String(format: String(localized: "about.version"), version))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("about.version")
                }
                Link(destination: website) {
                    Label(String(localized: "about.website"), systemImage: "globe")
                }.accessibilityIdentifier("about.website")
                Link(destination: source) {
                    Label(String(localized: "about.source"), systemImage: "chevron.left.forwardslash.chevron.right")
                }.accessibilityIdentifier("about.source")
                Text(String(localized: "about.note"))
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(MobileDesign.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
