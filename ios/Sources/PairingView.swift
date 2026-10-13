import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct PairingView: View {
    @Bindable var model: AppModel
    @State private var selectedBridge: DiscoveredBridge?
    @State private var selectedListing: SignedValue<EnrollmentBootstrap>?
    @State private var relayOrigin = ""
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
                        if model.addingDevice && !model.links.isEmpty {
                            Button { Task { await model.cancelEnrollment() }; model.addingDevice = false } label: {
                                Label(String(localized: "pair.back_to_sessions"), systemImage: "chevron.left")
                            }.buttonStyle(FloatingButtonStyle()).accessibilityIdentifier("pair.back")
                        }
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
                        discoverySection
                        advancedSection
                        if model.loading { ProgressView(String(localized: "pair.connecting")) }
                        if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
                }.scrollDismissesKeyboard(.interactively)
            }
            .alert(String(localized: "pair.trust_host"), isPresented: $confirmingTrust) {
                Button(String(localized: "pair.confirm_identity")) {
                    if let selectedListing { Task { await model.enrollListed(selectedListing) } }
                    else if let selectedBridge { Task { await model.enrollDiscovered(selectedBridge) } }
                }
                Button(String(localized: "pair.cancel"), role: .cancel) {}
            } message: {
                Text(trustMessage)
            }
            .task { await model.refreshRelayDirectory() }
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
    /// Name and full identity of the Mac the user is about to request access to.
    private var trustMessage: String {
        let name: String = selectedListing?.value.host.name ?? selectedBridge?.host.name ?? ""
        let id: String = selectedListing?.value.host.id ?? selectedBridge?.host.id ?? ""
        return [String(localized: "pair.trust_instructions"), name, id].joined(separator: "\n")
    }
    @ViewBuilder private var discoverySection: some View {
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
                    Button { selectedListing = nil; selectedBridge = bridge; confirmingTrust = true } label: {
                        hostRow(name: bridge.host.name, id: bridge.host.id, symbol: "wifi")
                    }.buttonStyle(.plain).disabled(model.isApproved(bridge.host.id))
                }
            }.modifier(FloatingSurface())
            relaySection
        }
    }
    private var advancedSection: some View {
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
    }
    /// Macs listed on known relays: reachable without a QR or the same network; the Mac owner still approves.
    private var relaySection: some View {
        VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
            HStack {
                Text(String(localized: "pair.relay")).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await model.refreshRelayDirectory() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "chat.refresh")).accessibilityIdentifier("pair.relay.refresh")
            }
            if model.relayOrigins.isEmpty { Text(String(localized: "pair.relay_hint")).font(.footnote).foregroundStyle(.secondary) }
            else if model.relayLoading && model.relayHosts.isEmpty { ProgressView(String(localized: "pair.relay_loading")).font(.footnote) }
            else if model.relayHosts.isEmpty && model.relayError == nil { Text(String(localized: "pair.relay_empty")).font(.footnote).foregroundStyle(.secondary) }
            ForEach(model.relayHosts, id: \.value.host.id) { entry in
                Button { selectedBridge = nil; selectedListing = entry; confirmingTrust = true } label: {
                    hostRow(name: entry.value.host.name, id: entry.value.host.id, symbol: "cloud")
                }.buttonStyle(.plain).disabled(model.isApproved(entry.value.host.id))
            }
            if let relayError = model.relayError { Text(relayError).font(.footnote).foregroundStyle(.red) }
            ForEach(model.relayOrigins, id: \.self) { origin in
                HStack {
                    Text(origin).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.removeRelayOrigin(origin) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(String(localized: "pair.relay_remove"))
                }
            }
            TextField(String(localized: "pair.relay_placeholder"), text: $relayOrigin).keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FloatingInput())
                .accessibilityIdentifier("pair.relay.origin")
            Button(String(localized: "pair.relay_add")) { let text = relayOrigin; relayOrigin = ""; Task { await model.addRelayOrigin(text) } }
                .buttonStyle(FloatingButtonStyle(fullWidth: true)).disabled(relayOrigin.trimmingCharacters(in: .whitespaces).isEmpty)
        }.modifier(FloatingSurface())
    }
    private func hostRow(name: String, id: String, symbol: String) -> some View {
        HStack(spacing: MobileDesign.rowGap) {
            Image(systemName: symbol).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).foregroundStyle(.primary)
                Text(String(id.prefix(16))).font(.caption.monospaced()).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.isApproved(id) { Label(String(localized: "pair.approved"), systemImage: "checkmark.seal").font(.caption).foregroundStyle(.green) }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }.frame(minHeight: MobileDesign.controlHeight).contentShape(Rectangle())
    }
}
