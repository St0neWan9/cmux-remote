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
        AppNavigationStack {
            WhitePage(title: String(localized: "app.title"), showsBack: false) {
                ScrollView {
                    VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                        VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                            Label(String(localized: "pair.intro"), systemImage: "macbook.and.iphone").font(.headline)
                            Text(String(localized: "pair.instructions")).font(.footnote).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                            Button { scanning = true } label: {
                                Label(String(localized: "pair.scan"), systemImage: "qrcode.viewfinder")
                            }.buttonStyle(FloatingButtonStyle(prominent: true, fullWidth: true))
                            Text(String(localized: "pair.scan_instructions")).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let enrollment = model.pendingEnrollment {
                            VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                                Text(String(localized: "pair.awaiting_owner")).font(.headline)
                                Text(String(localized: "pair.owner_instructions"))
                                Label(String(enrollment.request.value.clientID.prefix(12)).uppercased(), systemImage: "checkmark.shield")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                DisclosureGroup(String(localized: "pair.details")) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(enrollment.request.value.requestID).font(.caption.monospaced())
                                        Text(enrollment.request.value.clientID).font(.caption2.monospaced())
                                    }.textSelection(.enabled).padding(.top, 8)
                                }
                                Button(String(localized: "pair.cancel")) { Task { await model.cancelEnrollment() } }
                                    .buttonStyle(FloatingButtonStyle(fullWidth: true))
                            }.modifier(FloatingSurface())
                        } else {
                            VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                                Text(String(localized: "pair.nearby")).font(.headline)
                                if model.discovered.isEmpty { Text(String(localized: "pair.searching")).foregroundStyle(.secondary) }
                                ForEach(model.discovered) { bridge in
                                    Button { selectedBridge = bridge; confirmingTrust = true } label: {
                                        HStack(spacing: MobileDesign.rowGap) {
                                            Image(systemName: "laptopcomputer")
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(bridge.host.name).foregroundStyle(.primary)
                                                Text(String(bridge.host.id.prefix(16))).font(.caption.monospaced()).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                        }.frame(minHeight: MobileDesign.controlHeight).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }.modifier(FloatingSurface())
                        }
                        DisclosureGroup(String(localized: "pair.advanced")) {
                            VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                                VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                                    Text(String(localized: "pair.connection")).font(.headline)
                                    TextField(String(localized: "pair.host"), text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FloatingInput())
                                    TextField(String(localized: "pair.port"), text: $port).keyboardType(.numberPad).modifier(FloatingInput())
                                    SecureField(String(localized: "pair.token"), text: $token).textInputAutocapitalization(.never).modifier(FloatingInput())
                                    TextField(String(localized: "pair.fingerprint"), text: $fingerprint, axis: .vertical)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FloatingInput())
                                }
                                VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                                    Text(String(localized: "pair.import")).font(.headline)
                                    TextField(String(localized: "pair.json"), text: $json, axis: .vertical).lineLimit(3...8)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FloatingInput())
                                    Button(String(localized: "pair.import_enrollment")) { Task { await model.enrollQR(json.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                                        .buttonStyle(FloatingButtonStyle(fullWidth: true))
                                    Text(String(localized: "pair.legacy_notice")).font(.footnote).foregroundStyle(.secondary)
                                    Button(String(localized: "pair.fill")) {
                                        guard let value = try? JSONDecoder().decode(PairingConfiguration.self, from: Data(json.utf8)) else { model.error = String(localized: "pair.invalid"); return }
                                        host = value.host; port = String(value.port); token = value.token; fingerprint = value.certificateSHA256
                                    }.buttonStyle(FloatingButtonStyle(fullWidth: true))
                                }
                                Button {
                                    do {
                                        let pairing = try PairingConfiguration(host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? 0, token: token.trimmingCharacters(in: .whitespacesAndNewlines), certificateSHA256: fingerprint.trimmingCharacters(in: .whitespacesAndNewlines))
                                        Task { await model.pair(pairing) }
                                    } catch { model.error = String(localized: "pair.invalid") }
                                } label: {
                                    if model.loading { ProgressView() } else { Text(String(localized: "pair.connect")) }
                                }.buttonStyle(FloatingButtonStyle(prominent: true, fullWidth: true)).disabled(model.loading)
                            }.padding(.top, MobileDesign.rowGap)
                        }.modifier(FloatingSurface())
                        if model.loading { ProgressView(String(localized: "pair.connecting")) }
                        if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
                }.scrollDismissesKeyboard(.interactively)
            }
            .alert(String(localized: "pair.trust_host"), isPresented: $confirmingTrust) {
                Button(String(localized: "pair.confirm_identity")) { if let selectedBridge { Task { await model.enrollDiscovered(selectedBridge) } } }
                Button(String(localized: "pair.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "pair.trust_instructions") + "\n" + (selectedBridge?.host.id ?? ""))
            }
            .navigationDestination(isPresented: $scanning) {
                WhitePage(title: String(localized: "pair.scan")) {
                    QRScannerView { code in
                        scanning = false
                        do {
                            if code.hasPrefix("cmux-remote://enroll") { Task { await model.enrollQR(code) } }
                            else { let pairing = try PairingLinkCodec().decode(code); Task { await model.pair(pairing) } }
                        } catch { model.error = String(localized: "pair.invalid") }
                    }.ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }
}
