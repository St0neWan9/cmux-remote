import SwiftUI

/// First-use identity confirmation with a copyable, unhyphenated certificate fingerprint.
struct HostTrustSheet: View {
    let name: String
    let fingerprint: String
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "mac.trustTitle"), systemImage: "lock.shield").font(.title2)
            Text(String(localized: "mac.trustMessage"))
            Text(name).font(.headline)
            Text(fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "mac.cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(String(localized: "mac.trust"), action: confirm).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480)
    }
}
