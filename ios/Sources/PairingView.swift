import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct PairingView: View {
    @Bindable var model: AppModel
    @State private var selectedBridge: DiscoveredBridge?
    @State private var confirmingTrust = false
    @State private var host = ""
    @State private var port = "7740"
    @State private var token = ""
    @State private var fingerprint = ""
    @State private var json = ""
    @State private var scanning = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(String(localized: "pair.intro"), systemImage: "macbook.and.iphone")
                    Text(String(localized: "pair.instructions")).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { scanning = true } label: { Label(String(localized: "pair.scan"), systemImage: "qrcode.viewfinder").font(.headline) }
                    Text(String(localized: "pair.scan_instructions")).font(.footnote).foregroundStyle(.secondary)
                }
                if let enrollment = model.pendingEnrollment {
                    Section(String(localized: "pair.awaiting_owner")) {
                        Text(String(localized: "pair.owner_instructions"))
                        Text(enrollment.request.value.requestID).font(.caption.monospaced()).textSelection(.enabled)
                        Text(enrollment.request.value.clientID).font(.caption2.monospaced()).textSelection(.enabled)
                        Button(String(localized: "pair.cancel")) { Task { await model.cancelEnrollment() } }
                    }
                } else {
                    Section(String(localized: "pair.nearby")) {
                        if model.discovered.isEmpty { Text(String(localized: "pair.searching")).foregroundStyle(.secondary) }
                        ForEach(model.discovered) { bridge in
                            Button { selectedBridge = bridge; confirmingTrust = true } label: {
                                VStack(alignment: .leading) { Text(bridge.host.name); Text(String(bridge.host.id.prefix(16))).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                DisclosureGroup(String(localized: "pair.advanced")) {
                Section(String(localized: "pair.connection")) {
                    TextField(String(localized: "pair.host"), text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(String(localized: "pair.port"), text: $port).keyboardType(.numberPad)
                    SecureField(String(localized: "pair.token"), text: $token).textInputAutocapitalization(.never)
                    TextField(String(localized: "pair.fingerprint"), text: $fingerprint, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(String(localized: "pair.import")) {
                    TextField(String(localized: "pair.json"), text: $json, axis: .vertical).lineLimit(3...8).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(String(localized: "pair.import_enrollment")) { Task { await model.enrollQR(json.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    Text(String(localized: "pair.legacy_notice")).font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "pair.fill")) {
                        guard let value = try? JSONDecoder().decode(PairingConfiguration.self, from: Data(json.utf8)) else { model.error = String(localized: "pair.invalid"); return }
                        host = value.host; port = String(value.port); token = value.token; fingerprint = value.certificateSHA256
                    }
                }
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
                }
                if model.loading { Section { ProgressView(String(localized: "pair.connecting")) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(String(localized: "app.title"))
            .alert(String(localized: "pair.trust_host"), isPresented: $confirmingTrust) {
                Button(String(localized: "pair.confirm_identity")) { if let selectedBridge { Task { await model.enrollDiscovered(selectedBridge) } } }
                Button(String(localized: "pair.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "pair.trust_instructions") + "\n" + (selectedBridge?.host.id ?? ""))
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScannerView { code in
                        scanning = false
                        do {
                            if code.hasPrefix("cmux-remote://enroll") { Task { await model.enrollQR(code) } }
                            else { let pairing = try PairingLinkCodec().decode(code); Task { await model.pair(pairing) } }
                        }
                        catch { model.error = String(localized: "pair.invalid") }
                    }.ignoresSafeArea(edges: .bottom).navigationTitle(String(localized: "pair.scan"))
                        .toolbar { Button(String(localized: "pair.cancel")) { scanning = false } }
                }
            }
        }
    }
}
