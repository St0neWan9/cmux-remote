import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct CLIControlTests {
    @Test func savedSetupEnvironmentReachesEveryOfficialCLIInvocation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-cli")
        let script = """
        #!/bin/sh
        /bin/cat >/dev/null
        [ "$CMUX_SOCKET_CAPABILITY" = "fixture-capability" ] || exit 42
        [ "$CMUX_SOCKET_PATH" = "/fixture/cmux.sock" ] || exit 43
        /usr/bin/printf '{"accepted":true}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = CLIControlClient(executable: executable, socketPath: "/fixture/cmux.sock", environment: ["CMUX_SOCKET_CAPABILITY": "fixture-capability", "CMUX_SOCKET_PATH": "/fixture/cmux.sock"])
        #expect(try await client.request("system.tree", params: [:])["accepted"].bool == true)
        #expect(try await client.request("workspace.create", params: [:])["accepted"].bool == true)
    }
    @Test(arguments: ["workspace.create", "surface.create", "surface.move", "surface.split_off", "surface.reorder", "surface.close"])
    func lostMirrorWorkspaceCreateIsOutcomeUnknown(method: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-cli")
        try Data("#!/bin/sh\n/bin/cat >/dev/null\nexit 42\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        do {
            _ = try await CLIControlClient(executable: executable, socketPath: "/example/cmux.sock").request(method, params: [:])
            Issue.record("Expected an unknown mutation outcome")
        } catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
    }
    @Test func aFastFailedReadIsRetriedOnceWhileAMutationIsNeverRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-cli")
        let counter = directory.appendingPathComponent("invocations")
        let script = """
        #!/bin/sh
        /bin/cat >/dev/null
        n=$(( $(/bin/cat "\(counter.path)" 2>/dev/null || echo 0) + 1 )); echo "$n" > "\(counter.path)"
        [ "$5" = "workspace.create" ] && exit 42
        [ "$n" = 1 ] && exit 42
        /usr/bin/printf '{"accepted":true}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        // A read whose first CLI invocation fails quickly is retried once and then succeeds.
        let client = CLIControlClient(executable: executable, socketPath: "/example/cmux.sock")
        #expect(try await client.request("system.tree", params: [:])["accepted"].bool == true)
        #expect(try String(contentsOf: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        // A mutation must never repeat: the first failure already made the outcome unknown.
        do {
            _ = try await client.request("workspace.create", params: [:])
            Issue.record("Expected an unknown mutation outcome")
        } catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        #expect(try String(contentsOf: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }
    @Test func officialRPCUsesPrivateStdinAndDecodesPlainResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-cli")
        let script = """
        #!/bin/sh
        if [ "$5" != "mobile.chat.send" ] || [ "$6" != "-" ]; then exit 3; fi
        input=$(/bin/cat)
        case "$input" in *"fixture-prompt"*) /usr/bin/printf '{"submitted":true}' ;; *) exit 4 ;; esac
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = try await CLIControlClient(executable: executable, socketPath: "/example/cmux.sock").request("mobile.chat.send", params: ["text": .string("fixture-prompt")])
        #expect(result["submitted"].bool == true)
    }
}
