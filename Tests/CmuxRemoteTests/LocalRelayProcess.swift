import Foundation
import Darwin
import CmuxRemoteCore
import CmuxRemoteBridge

/// Starts only a task-owned Miniflare fixture and reads its bounded readiness line.
struct LocalRelayProcess {
    let process: Process
    let origin: String
    let tls: BridgeState
    let input: Pipe
    let output: Pipe
    static func start(root: URL) async throws -> LocalRelayProcess {
        let tls = BridgeState(directory: root.appendingPathComponent("relay-tls")); try tls.initialize()
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", project.appendingPathComponent("cloudflare/tests/local-server.mjs").path, tls.certificate, tls.key]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let input = Pipe(); process.standardInput = input
        try process.run()
        do {
            let fd = output.fileHandleForReading.fileDescriptor
            let line = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await Task.detached {
                        var bytes = Data(), byte: UInt8 = 0
                        while bytes.count < 1024 {
                            guard Darwin.read(fd, &byte, 1) == 1 else { throw BridgeError("invalid_response", "The local relay did not start.") }
                            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }; bytes.append(byte)
                        }
                        throw BridgeError("invalid_response", "The relay readiness line exceeds its bound.")
                    }.value
                }
                group.addTask { try await Task.sleep(for: .seconds(15)); if process.isRunning { process.terminate() }; throw BridgeError("socket_unavailable", "The local relay startup timed out.") }
                defer { group.cancelAll() }; return try await group.next()!
            }
            return LocalRelayProcess(process: process, origin: try RelayOrigin(line).value, tls: tls, input: input, output: output)
        } catch { if process.isRunning { process.terminate() }; throw error }
    }
    func stop() { if process.isRunning { process.terminate() } }
}
