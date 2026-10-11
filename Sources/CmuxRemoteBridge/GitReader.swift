import Foundation
import CmuxRemoteCore

/// Executes fixed Git reads without a shell or external diff helpers.
public struct GitReader: Sendable {
    public init() {}
    public func run(directory: String, arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process(); let output = Pipe(); let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--no-pager", "-c", "core.fsmonitor=false", "-C", directory] + arguments
            process.environment = ["PATH": "/usr/bin:/bin", "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
            process.standardOutput = output; process.standardError = errors
            let completion = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
            process.terminationHandler = { child in completion.continuation.yield(child.terminationStatus); completion.continuation.finish() }
            try process.run()
            // A process deadline is intended behavior, not a state-settling sleep.
            let deadline = Task {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled && process.isRunning { process.terminate() }
            }
            defer { deadline.cancel() }
            let outFD = output.fileHandleForReading.fileDescriptor
            let errFD = errors.fileHandleForReading.fileDescriptor
            async let stdout = Task.detached { Self.drain(outFD, cap: 2_097_152) }.value
            async let stderr = Task.detached { Self.drain(errFD, cap: 16_384) }.value
            let status = await withTaskCancellationHandler {
                var iterator = completion.stream.makeAsyncIterator()
                return await iterator.next()
            } onCancel: { if process.isRunning { process.terminate() } }
            let data = await stdout; _ = await stderr
            guard status == 0 else { throw BridgeError("not_a_repository", "Git could not read this project.", status: 422) }
            guard data.count <= 2_097_152 else { throw BridgeError("too_large", "The diff exceeds the transfer limit.", status: 413) }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
    private static func drain(_ fd: Int32, cap: Int) -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            if data.count <= cap { data.append(contentsOf: buffer.prefix(count)) }
        }
        return data
    }
}
