import Foundation
import CmuxRemoteCore

/// Invokes the official CLI's local RPC path so cmux retains its own socket authority.
public struct CLIControlClient: CmuxControlling {
    private let executable: URL
    private let socketPath: String
    public init(executable: URL, socketPath: String) { self.executable = executable; self.socketPath = socketPath }
    public func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        let input = try JSONEncoder().encode(JSONValue.object(params))
        guard input.count <= 1_048_576 else { throw BridgeError("too_large", "The request is too large.", status: 413) }
        let executable = executable; let socketPath = socketPath
        return try await Task.detached {
            // A private inherited stdin file avoids putting prompt contents in argv or pipe races.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-remote-rpc-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let inputURL = temporary.appendingPathComponent("params.json")
            try input.write(to: inputURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
            let source = try FileHandle(forReadingFrom: inputURL); defer { try? source.close() }
            let process = Process(); let output = Pipe(); let errors = Pipe()
            process.executableURL = executable; process.arguments = ["--socket", socketPath, "--json", "rpc", method, "-"]
            process.standardInput = source; process.standardOutput = output; process.standardError = errors
            let completion = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
            process.terminationHandler = { child in completion.continuation.yield(child.terminationStatus); completion.continuation.finish() }
            try process.run()
            let deadline = Task { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled && process.isRunning { process.terminate() } }
            defer { deadline.cancel() }
            let outFD = output.fileHandleForReading.fileDescriptor; let errFD = errors.fileHandleForReading.fileDescriptor
            async let stdout = Task.detached { Self.drain(outFD, cap: 8_388_608) }.value
            async let stderr = Task.detached { Self.drain(errFD, cap: 16_384) }.value
            let status = await withTaskCancellationHandler {
                var iterator = completion.stream.makeAsyncIterator(); return await iterator.next()
            } onCancel: { if process.isRunning { process.terminate() } }
            let data = await stdout; _ = await stderr
            guard status == 0 else {
                let mutation = ["mobile.chat.send", "mobile.chat.interrupt", "mobile.terminal.input", "workspace.create", "workspace.select", "workspace.group.create", "workspace.group.add", "workspace.reorder_many", "surface.create", "surface.split", "surface.action", "surface.move", "surface.split_off", "surface.reorder", "surface.close", "feed.permission.reply", "feed.question.reply", "feed.exit_plan.reply"].contains(method)
                throw BridgeError(mutation ? "outcome_unknown" : "socket_unavailable", mutation ? "Inspect the task before repeating this operation." : "Open cmux and check the official CLI's socket access.", status: 503)
            }
            guard data.count <= 8_388_608, let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw BridgeError("invalid_response", "The official CLI returned an invalid response.", status: 502) }
            if value["ok"].bool == false { throw BridgeError(value["error"]["code"].string ?? "socket_denied", "cmux could not complete this operation.", status: 502) }
            return value["ok"].bool == true ? value["result"] : value
        }.value
    }
    private static func drain(_ fd: Int32, cap: Int) -> Data {
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 8192)
        while true { let count = read(fd, &bytes, bytes.count); if count <= 0 { break }; if data.count <= cap { data.append(contentsOf: bytes.prefix(count)) } }
        return data
    }
}
