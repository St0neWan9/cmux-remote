import Foundation
import TermRemoteCore
import TermRemoteBridge

/// A plain-text desktop viewer for any provider's terminal, through the
/// owner-only local channel. It never owns, resizes or focuses the terminal.
struct ViewCommand {
    func run(options: CLIOptions, state: BridgeState) async throws {
        let socket = UnixSocketClient(path: state.directory.appendingPathComponent("owner.sock").path)
        var terminal = options.value("terminal")
        if terminal == nil {
            guard let space = options.value("space") else {
                throw BridgeError("invalid_input", "Pass --space (to pick its first terminal) or --terminal.")
            }
            let raw = try await socket.request("providers.terminals", params: ["space": .string(space)])
            let list = try JSONDecoder().decode(TerminalList.self, from: JSONEncoder().encode(raw))
            guard let first = list.terminals.first else {
                throw BridgeError("terminal_not_found", "That space has no terminal.", status: 404)
            }
            print("Viewing \(first.title) [\(first.id)]")
            terminal = first.id
        }
        let terminalID = terminal!
        let interactive = isatty(STDOUT_FILENO) == 1
        let polling = Task {
            var last = ""
            while !Task.isCancelled {
                if let raw = try? await socket.request("providers.screen", params: ["terminal": .string(terminalID)]),
                   let snapshot = try? JSONDecoder().decode(TerminalSnapshot.self, from: JSONEncoder().encode(raw)),
                   snapshot.text != last {
                    last = snapshot.text
                    if interactive { print("\u{1b}[H\u{1b}[2J", terminator: "") }
                    print(snapshot.text)
                    if interactive { print("[view] type a command and press Return; :esc :ctrlc :tab send a key; :q quits") }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { polling.cancel() }
        while let line = readLine() {
            if line == ":q" { break }
            let text: String
            let submit: Bool
            switch line {
            case ":esc": text = "\u{1b}"; submit = false
            case ":ctrlc": text = "\u{3}"; submit = false
            case ":tab": text = "\t"; submit = false
            default: text = line; submit = true
            }
            _ = try? await socket.request("providers.input", params: [
                "terminal": .string(terminalID), "text": .string(text), "submit": .bool(submit),
                "operation_id": .string(UUID().uuidString)
            ])
        }
    }
}
