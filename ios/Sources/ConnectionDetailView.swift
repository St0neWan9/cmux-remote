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
                VStack(alignment: .leading, spacing: 24) {
                    Label(host, systemImage: "laptopcomputer").font(.title3.weight(.semibold))
                    if loading { ProgressView(String(localized: "pair.connecting")) }
                    if status != nil { Label(String(localized: "connection.reachable"), systemImage: "checkmark.shield").foregroundStyle(.green) }
                    if let error { Text(error).foregroundStyle(.red) }
                    VStack(alignment: .leading, spacing: 12) {
                        if let endpoint { LabeledContent(String(localized: "connection.endpoint"), value: endpoint) }
                        if let protocolName = status?["protocol"].string { LabeledContent(String(localized: "connection.protocol"), value: protocolName) }
                        if let identity { Text(String(localized: "connection.identity")).font(.headline); Text(identity).font(.caption.monospaced()).textSelection(.enabled) }
                        if let certificate { Text(String(localized: "pair.fingerprint")).font(.headline); Text(certificate).font(.caption.monospaced()).textSelection(.enabled) }
                    }.modifier(FloatingSurface())
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "connection.permissions")).font(.headline)
                        ForEach(ClientCapability.allCases.filter(client.allows), id: \.rawValue) { capability in
                            Label(capability.localizedTitle, systemImage: "checkmark")
                        }
                        Text(String(localized: identity == nil ? "pair.legacy_notice" : "connection.owner_managed")).font(.footnote).foregroundStyle(.secondary)
                    }.modifier(FloatingSurface())
                    HStack {
                        Button(String(localized: "chat.refresh")) { Task { await refresh() } }
                        Button(String(localized: "pair.disconnect"), role: .destructive, action: disconnect)
                    }.buttonStyle(FloatingButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.refreshable { await refresh() }
        }.task { await refresh() }
    }
    private func refresh() async {
        guard !loading else { return }; loading = true; status = nil; defer { loading = false }
        do { status = try await client.get("/v1/status", as: JSONValue.self); error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
}
