import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Explicit local owner actions. Approval never happens automatically after a scan.
struct OwnerCommand {
    func run(family: String, options: CLIOptions, state: BridgeState, port: Int) async throws {
        let verb = options.args.first ?? "pending"
        let socket = UnixSocketClient(path: state.directory.appendingPathComponent("owner.sock").path)
        var params: [String: JSONValue] = [:]
        let method = family + "." + verb
        switch method {
        case "enrollment.open":
            guard let host = options.value("host") ?? LANAddressResolver().address() else { throw BridgeError("lan_unavailable", "Choose a reachable host address.") }
            params = ["host": .string(host), "port": .number(Double(port)), "seconds": .number(Double(Int(options.value("seconds") ?? "300") ?? 300))]
            let workspaces = options.values("workspace"); if !workspaces.isEmpty { params["workspaces"] = .array(workspaces.map(JSONValue.string)) }
        case "enrollment.approve":
            guard options.args.count >= 2 else { throw BridgeError("invalid_input", "Choose an exact pending request ID.") }
            let workspaces = options.values("workspace")
            let explicit = options.values("capability")
            var capabilities: [ClientCapability]
            if explicit.isEmpty {
                capabilities = options.contains("control") ? [.workspaceRead, .conversationRead, .projectRead, .feedRead, .conversationControl, .feedReply] : [.workspaceRead, .conversationRead, .projectRead, .feedRead]
                // Starting sessions comes with control only when the device asked for it; approval never expands a request.
                if options.contains("control") {
                    let pending = try JSONDecoder().decode([EnrollmentRequest].self, from: JSONEncoder().encode(await socket.request("enrollment.pending", params: [:])))
                    if pending.first(where: { $0.requestID == options.args[1] })?.scope.capabilities.contains(.conversationStart) == true { capabilities.append(.conversationStart) }
                }
            }
            else {
                guard explicit.allSatisfy({ ClientCapability(rawValue: $0) != nil }) else { throw BridgeError("invalid_scope", "Unknown capability.") }
                capabilities = explicit.compactMap(ClientCapability.init(rawValue:))
            }
            let scope = ClientScope(workspaces: workspaces, capabilities: capabilities); try scope.validate()
            params = ["request_id": .string(options.args[1]), "scope": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(scope))]
        case "enrollment.deny": guard options.args.count >= 2 else { throw BridgeError("invalid_input", "Choose an exact request ID.") }; params["request_id"] = .string(options.args[1])
        case "clients.revoke": guard options.args.count >= 2 else { throw BridgeError("invalid_input", "Choose an exact client ID.") }; params["client_id"] = .string(options.args[1])
        case "enrollment.pending", "enrollment.close", "clients.list": break
        default: throw BridgeError("invalid_input", "Unknown local owner command.")
        }
        let result = try await socket.request(method, params: params)
        if method == "enrollment.open" {
            let bootstrap = try JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: JSONEncoder().encode(result))
            if options.value("format") == "json" { print(String(decoding: try JSONEncoder().encode(bootstrap), as: UTF8.self)) }
            else { print("Scan to request enrollment. Approve the exact device on this Mac."); print(try TerminalQRCode().render(EnrollmentLinkCodec().encode(bootstrap))) }
        } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        }
    }
}
