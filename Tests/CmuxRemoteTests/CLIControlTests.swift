import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct CLIControlTests {
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
