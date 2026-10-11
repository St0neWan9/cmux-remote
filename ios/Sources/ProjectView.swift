import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct ProjectView: View {
    let session: SessionDescriptor
    let client: RemoteClient
    @State private var content = ""
    @State private var filePath = ""
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(String(localized: "project.path"), text: $filePath).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button(String(localized: "project.file")) { Task { await load("file", query: ["path": filePath]) } }.disabled(filePath.isEmpty)
                    Button(String(localized: "project.diff")) { Task { await load("diff", query: filePath.isEmpty ? [:] : ["path": filePath]) } }
                    Button(String(localized: "project.changes")) { Task { await changes() } }
                }.buttonStyle(.bordered)
                if let error { Text(error).foregroundStyle(.red) }
                Text(content).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding()
        }.navigationTitle(String(localized: "project.title")).task { await changes() }
    }
    private func load(_ resource: String, query: [String: String]) async {
        do { let value = try await client.get("/v1/sessions/\(session.id)/\(resource)", query: query, as: TextFileSnapshot.self); content = value.text; error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
    private func changes() async {
        do { let value = try await client.get("/v1/sessions/\(session.id)/changes", as: JSONValue.self); content = (value["entries"].array ?? []).compactMap(\.string).joined(separator: "\n"); error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
}
