import SwiftUI
import TermRemoteCore
import TermRemoteClient

/// A provider-neutral terminal without a proved Agent. It is a bounded text
/// screen, not a terminal emulator, and every input is an explicit operation.
struct TerminalSessionView: View {
    let session: SessionDescriptor
    let client: RemoteClient
    let hostName: String
    @State private var text = ""
    @State private var draft = ""
    @State private var error: String?
    @State private var busy = false
    private var terminalID: String { session.surfaceID ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 6)
            }
            HStack(spacing: 8) {
                TextField("Command", text: $draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Button { Task { await send() } } label: {
                    Text(String(localized: "chat.send"))
                }.buttonStyle(.borderedProminent).disabled(busy || terminalID.isEmpty)
            }.padding(12)
            HStack(spacing: 8) {
                Button { Task { await key("\u{1b}") } } label: { Text(verbatim: "Esc") }
                Button { Task { await key("\u{3}") } } label: { Text(verbatim: "Ctrl-C") }
                Button { Task { await key("\t") } } label: { Text(verbatim: "Tab") }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }.buttonStyle(.bordered).controlSize(.small)
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Text(hostName).font(.caption).foregroundStyle(.secondary) } }
        .task(id: terminalID) { await poll() }
    }

    private func poll() async {
        guard !terminalID.isEmpty else { return }
        while !Task.isCancelled {
            var changed = false
            do {
                let snapshot = try await client.get("/v3/terminals/\(terminalID)/screen", as: TerminalSnapshot.self)
                changed = snapshot.text != text
                text = snapshot.text
                error = nil
            } catch {
                if !Task.isCancelled { self.error = ErrorPresentation().message(error) }
            }
            // New output earns a fast follow-up; a quiet screen costs one poll a second.
            do { try await Task.sleep(for: changed ? .milliseconds(250) : .seconds(1)) } catch { return }
        }
    }

    private func send() async {
        let value = draft
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await client.post("/v3/terminals/\(terminalID)/input",
                                      body: TerminalInputRequest(text: value, submit: true, operationID: UUID()),
                                      as: MutationReceipt.self)
            draft = ""; error = nil
        } catch { self.error = ErrorPresentation().message(error) }
    }

    private func key(_ value: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await client.post("/v3/terminals/\(terminalID)/input",
                                      body: TerminalInputRequest(text: value, submit: false, operationID: UUID()),
                                      as: MutationReceipt.self)
            error = nil
        } catch { self.error = ErrorPresentation().message(error) }
    }
}
