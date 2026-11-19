import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

/// Exercises the Rex provider against an isolated server on its own port and
/// state directory. It never reads, drives or stops the owner's Rex server.
/// The test is skipped when the `rex` binary is not installed.
@Suite struct RexProviderTests {
    @Test func readsARealRexSessionAndWritesToItsTerminal() async throws {
        guard let executable = Self.rexExecutable() else { return }
        for _ in 0..<3 {
            let port = Int.random(in: 20_000...60_000)
            let state = FileManager.default.temporaryDirectory.appendingPathComponent("rex-provider-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["server", "run", "--listen", "127.0.0.1:\(port)", "--allow-anonymous",
                                 "--state-dir", state.path, "--restore=false", "--log-format", "text"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return }
            defer {
                if process.isRunning { process.terminate() }
                for _ in 0..<30 where process.isRunning { Darwin.usleep(100_000) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: state)
            }
            let endpoint = RexEndpoint.tcp(host: "127.0.0.1", port: port, tls: false)
            let client = RexControlClient(endpoint: endpoint)
            var welcome: RexControlClient.Welcome?
            for _ in 0..<40 {
                if let value = try? await client.connect() { welcome = value; break }
                try await Task.sleep(for: .milliseconds(150))
            }
            guard let welcome else {
                await client.close()
                continue
            }
            #expect(welcome.apiServerRevision >= 16)

            let created = try await client.request("session.create", [
                "label": .string("provider-fixture"),
                "initial_windows": .array([.object([
                    "layout": .object(["block": .object(["flavor": .string("com.superlogical.terminal.shell")])])
                ])])
            ])
            let sessionID = try #require(created["session_id"].string)
            let provider = RexProvider(endpoint: endpoint, label: "Rex fixture", mutations: MutationLedger())
            let spaces = try await provider.spaces()
            let space = try #require(spaces.first(where: { $0.title == "provider-fixture" }))
            let terminals = try await provider.terminals(spaceID: space.id)
            let terminal = try #require(terminals.first)
            #expect(terminal.state == "running" || terminal.state == "unknown")

            let operation = UUID()
            let receipt = try await provider.send(
                TerminalInputRequest(text: "echo REX_PROVIDER_OK", submit: true, operationID: operation),
                clientID: "fixture-device", terminalID: terminal.id, authorize: {})
            #expect(receipt.operationID == operation)
            #expect(receipt.accepted)

            var text = ""
            for _ in 0..<25 {
                text = try await provider.snapshot(terminalID: terminal.id).text
                if text.contains("REX_PROVIDER_OK") { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            #expect(text.contains("REX_PROVIDER_OK"))

            _ = try? await client.request("session.destroy", ["session_id": .string(sessionID)])
            await provider.close()
            await client.close()
            return
        }
    }

    private static func rexExecutable() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", "command -v rex"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }
}
