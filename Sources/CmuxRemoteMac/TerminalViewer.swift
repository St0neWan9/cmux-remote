import Foundation
import Darwin
import CmuxRemoteCore
import CmuxRemoteBridge

/// Foreground VT viewer; its lifetime affects only a local projection.
public struct TerminalViewer: Sendable {
    private let owner: any CmuxControlling
    public init(owner: any CmuxControlling) { self.owner = owner }
    public func run(projectionID: UUID) async throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { throw BridgeError("terminal_required", "Run mirror view inside a cmux terminal.") }
        let params: [String: JSONValue] = ["projection_id": .string(projectionID.uuidString)]
        let first = try await snapshot(params)
        var original = termios(); guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw BridgeError("terminal_unavailable", "Could not read terminal mode.") }
        var raw = original; cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw BridgeError("terminal_unavailable", "Could not enter viewer input mode.") }
        defer {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            // Leave the containing shell with no viewer-generated event reports.
            _ = Data("\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1004l\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l\u{1B}[?2004l\u{1B}[?1l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l".utf8).withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }
        }
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }
        let input = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        // DispatchSource is the low-level cancellable readiness seam; mutable buffers are callback-local.
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            if count > 0 {
                if case .dropped = input.continuation.yield(Data(bytes.prefix(count))) {
                    input.continuation.finish(throwing: BridgeError("input_queue_full", "Viewer input was not retried."))
                }
            } else if count == 0 { input.continuation.finish() }
            else if errno != EAGAIN { input.continuation.finish(throwing: BridgeError("terminal_unavailable", "Viewer input closed.")) }
        }
        source.resume(); defer { source.cancel() }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    var last = Data()
                    var presentation = TerminalPresentationSequence()
                    var next = first
                    while !Task.isCancelled {
                        guard next.runtimeEpoch == first.runtimeEpoch else { throw BridgeError("stale_binding", "The producer changed; viewer detached.") }
                        if next.bytes != last { try TerminalOutputWriter(descriptor: STDOUT_FILENO).write(presentation.next(next)); last = next.bytes }
                        // Intentional bounded snapshot cadence; the local API has no output subscription.
                        try await Task.sleep(for: .milliseconds(300))
                        next = try await snapshot(params)
                    }
                }
                group.addTask {
                    var buffer = Data()
                    for try await chunk in input.stream {
                        if chunk.contains(0x1D) { return } // Ctrl-] detaches locally.
                        guard first.allowsInput else { continue }
                        buffer.append(chunk)
                        guard buffer.count <= 16_384 else { throw BridgeError("invalid_input", "Input exceeds the viewer limit.") }
                        guard let text = String(data: buffer, encoding: .utf8) else { continue }
                        buffer.removeAll(keepingCapacity: true)
                        let request = MirrorInputRequest(runtimeEpoch: first.runtimeEpoch, text: text)
                        var values = params
                        values["input"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
                        _ = try await owner.request("mirror.input", params: values)
                    }
                }
                defer { group.cancelAll(); input.continuation.finish() }
                _ = try await group.next()
            }
        } catch {
            var failureParams = params
            failureParams["reason"] = .string((error as? BridgeError)?.code ?? "viewer_failed")
            _ = try? await owner.request("mirror.detach", params: failureParams)
            throw error
        }
        _ = try? await owner.request("mirror.detach", params: params)
    }
    private func snapshot(_ params: [String: JSONValue]) async throws -> MirrorTerminalSnapshot {
        try await MirrorSnapshotReader(owner: owner).read(params)
    }
}
