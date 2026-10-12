import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteMac

/// Thin discover/connect arguments over the same resident authority as the GUI.
struct ConnectionCommand {
    func run(command: String, options: CLIOptions, state: BridgeState) async throws {
        let owner = UnixSocketClient(path: state.directory.appendingPathComponent("owner.sock").path)
        let connector = MacClientConnector(owner: owner)
        let result: JSONValue
        if command == "discover" {
            result = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(await connector.discover()))
        } else if options.args.first == "status" { result = try await connector.status() }
        else if options.args.first == "cancel" { result = try await owner.request("mac.enrollment.cancel", params: [:]) }
        else if options.args.first == "forget" {
            guard options.args.count > 1 else { throw BridgeError("invalid_input", "Use connect forget HOST_ID.") }
            result = try await owner.request("mac.forget", params: ["host_id": .string(options.args[1])])
        }
        else {
            guard let host = options.value("host") ?? options.args.first else { throw BridgeError("invalid_input", "Use connect HOST_ID [--trust-certificate SHA256], connect status, or connect cancel.") }
            result = try await connector.connect(hostID: host, confirmedCertificate: options.value("trust-certificate"),
                clientName: options.value("name") ?? Host.current().localizedName ?? "Mac Companion")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
    }
}
