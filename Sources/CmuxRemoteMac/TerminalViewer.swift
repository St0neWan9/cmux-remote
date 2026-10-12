import Foundation
import Darwin
import CmuxRemoteCore
import CmuxRemoteBridge

/// Foreground VT viewer; its lifetime affects only a local projection.
public struct TerminalViewer: Sendable {
    private let owner: any CmuxControlling
    private let viewport: @Sendable () -> (columns: Int, rows: Int)?
    public init(owner: any CmuxControlling, viewport: @escaping @Sendable () -> (columns: Int, rows: Int)? = {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return nil }
        return (Int(size.ws_col), Int(size.ws_row))
    }) { self.owner = owner; self.viewport = viewport }
    public func run(projectionID: UUID) async throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { throw BridgeError("terminal_required", "Run mirror view inside a cmux terminal.") }
        let params: [String: JSONValue] = ["projection_id": .string(projectionID.uuidString)]
        let first = try await snapshot(params)
        let viewing = TerminalViewportState()
        var original = termios(); guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw BridgeError("terminal_unavailable", "Could not read terminal mode.") }
        var raw = original; cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw BridgeError("terminal_unavailable", "Could not enter viewer input mode.") }
        defer {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            // Leave the containing shell with no viewer-generated event reports.
            _ = Data("\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1004l\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1007l\u{1B}[?1015l\u{1B}[?1016l\u{1B}[?2004l\u{1B}[?1l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l".utf8).withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }
        }
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }
        let input = TerminalInputBuffer()
        // DispatchSource is the low-level cancellable readiness seam; mutable buffers are callback-local.
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            if count > 0 {
                do { try input.append(Data(bytes.prefix(count))) }
                catch { input.finish(throwing: error) }
            } else if count == 0 { input.finish() }
            else if errno != EAGAIN { input.finish(throwing: BridgeError("terminal_unavailable", "Viewer input closed.")) }
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
                        let fitted: MirrorTerminalSnapshot
                        if let size = viewport() {
                            let top = await viewing.topRow(for: next, localRows: size.rows)
                            fitted = try TerminalViewportPresentation().render(next, columns: size.columns, rows: size.rows, topRow: top)
                        }
                        else { fitted = next }
                        if fitted.bytes != last {
                            var bytes = presentation.next(fitted)
                            // Wheel reports are local navigation, never arrow keys or remote pointer input.
                            bytes.append(Data("\u{1B}[?1007l\u{1B}[?1000h\u{1B}[?1006h".utf8))
                            try TerminalOutputWriter(descriptor: STDOUT_FILENO).write(bytes); last = fitted.bytes
                        }
                        // Intentional bounded snapshot cadence; the local API has no output subscription.
                        try await Task.sleep(for: .milliseconds(300))
                        next = try await snapshot(params)
                    }
                }
                group.addTask {
                    var buffer = Data()
                    var pointer = TerminalPointerInputDecoder()
                    var expiry: Task<Void, Never>?
                    var flushAt: ContinuousClock.Instant?
                    let clock = ContinuousClock()
                    defer { expiry?.cancel() }
                    for try await _ in input.notifications {
                        try Task.checkCancellation()
                        let chunk = try input.take()
                        let events: [TerminalPointerInputDecoder.Event]
                        if chunk.isEmpty {
                            guard let deadline = flushAt, clock.now >= deadline else { continue }
                            events = pointer.flushPending()
                        } else { events = try pointer.consume(chunk) }
                        expiry?.cancel(); expiry = nil; flushAt = nil
                        if pointer.hasPending {
                            flushAt = clock.now.advanced(by: .milliseconds(50))
                            expiry = Task { try? await Task.sleep(for: .milliseconds(50)); if !Task.isCancelled { input.wake() } }
                        }
                        for event in events {
                            try Task.checkCancellation()
                            if case .scroll(let delta) = event { await viewing.scroll(delta); continue }
                            if case .paste(let bytes) = event {
                                guard first.allowsInput else { continue }
                                guard first.pasteSupported == true else { throw BridgeError("mirror_unsupported", "Update the remote Bridge before pasting.") }
                                guard buffer.isEmpty, let text = String(data: bytes, encoding: .utf8) else { throw BridgeError("invalid_input", "Invalid paste text.") }
                                await viewing.followCursor()
                                let request = MirrorInputRequest(runtimeEpoch: first.runtimeEpoch, text: text, paste: true)
                                var values = params
                                values["input"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
                                _ = try await owner.request("mirror.input", params: values)
                                continue
                            }
                            guard case .keyboard(let chunk) = event else { continue }
                            if chunk.contains(0x1D) { return } // Ctrl-] detaches locally.
                            guard first.allowsInput else { continue }
                            await viewing.followCursor()
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
                }
                defer { group.cancelAll(); input.finish() }
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
