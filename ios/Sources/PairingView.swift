import SwiftUI
import CmuxRemoteCore

struct PairingView: View {
    @Bindable var model: AppModel
    @State private var host = ""
    @State private var port = "7740"
    @State private var token = ""
    @State private var fingerprint = ""
    @State private var json = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(String(localized: "pair.intro"), systemImage: "macbook.and.iphone")
                    Text(String(localized: "pair.instructions")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(String(localized: "pair.connection")) {
                    TextField(String(localized: "pair.host"), text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(String(localized: "pair.port"), text: $port).keyboardType(.numberPad)
                    SecureField(String(localized: "pair.token"), text: $token).textInputAutocapitalization(.never)
                    TextField(String(localized: "pair.fingerprint"), text: $fingerprint, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(String(localized: "pair.import")) {
                    TextField(String(localized: "pair.json"), text: $json, axis: .vertical).lineLimit(3...8).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(String(localized: "pair.fill")) {
                        guard let value = try? JSONDecoder().decode(PairingConfiguration.self, from: Data(json.utf8)) else { model.error = String(localized: "pair.invalid"); return }
                        host = value.host; port = String(value.port); token = value.token; fingerprint = value.certificateSHA256
                    }
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        do {
                            let pairing = try PairingConfiguration(host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? 0, token: token.trimmingCharacters(in: .whitespacesAndNewlines), certificateSHA256: fingerprint.trimmingCharacters(in: .whitespacesAndNewlines))
                            Task { await model.pair(pairing) }
                        } catch { model.error = String(localized: "pair.invalid") }
                    } label: {
                        if model.loading { ProgressView() } else { Text(String(localized: "pair.connect")) }
                    }.disabled(model.loading)
                }
            }.navigationTitle(String(localized: "app.title"))
        }
    }
}
