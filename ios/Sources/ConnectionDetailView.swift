import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// Connection inspection exposes only public trust and the approved resource capabilities.
struct ConnectionDetailView: View {
    let client: RemoteClient
    let host: String
    let identity: String?
    let certificate: String?
    let endpoint: String?
    let disconnect: () -> Void
    @State private var status: JSONValue?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        WhitePage(title: String(localized: "connection.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    Label(host, systemImage: "laptopcomputer").font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if loading { ProgressView(String(localized: "pair.connecting")) }
                    if status != nil { Label(String(localized: "connection.reachable"), systemImage: "checkmark.shield").foregroundStyle(.green) }
                    if let error { Text(error).foregroundStyle(.red) }
                    VStack(alignment: .leading, spacing: 12) {
                        if let endpoint { detail(String(localized: "connection.endpoint"), value: endpoint) }
                        if let protocolName = status?["protocol"].string { detail(String(localized: "connection.protocol"), value: protocolName) }
                        if let identity { detail(String(localized: "connection.identity"), value: identity, monospaced: true) }
                        if let certificate { detail(String(localized: "pair.fingerprint"), value: certificate, monospaced: true) }
                    }.modifier(FloatingSurface())
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "connection.permissions")).font(.headline)
                        ForEach(ClientCapability.allCases.filter(client.allows), id: \.rawValue) { capability in
                            Label(capability.localizedTitle, systemImage: "checkmark")
                        }
                        Text(String(localized: identity == nil ? "pair.legacy_notice" : "connection.owner_managed")).font(.footnote).foregroundStyle(.secondary)
                    }.modifier(FloatingSurface())
                    VStack(spacing: MobileDesign.rowGap) {
                        Button(String(localized: "chat.refresh")) { Task { await refresh() } }.disabled(loading)
                        NavigationLink(destination: DiagnosticLogView()) {
                            Text("诊断日志").frame(maxWidth: .infinity)
                        }.buttonStyle(FloatingButtonStyle(fullWidth: true))
                        Button(String(localized: "connection.remove"), role: .destructive, action: disconnect)
                        Text(String(localized: "connection.remove_hint")).font(.footnote).foregroundStyle(.secondary)
                    }.buttonStyle(FloatingButtonStyle(fullWidth: true))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
            }.refreshable { await refresh() }
        }.task { await refresh() }
    }
    private func detail(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(value).font(monospaced ? .caption.monospaced() : .callout)
                .foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func refresh() async {
        guard !loading else { return }; loading = true; status = nil; defer { loading = false }
        do { status = try await client.get("/v1/status", as: JSONValue.self); error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
}
