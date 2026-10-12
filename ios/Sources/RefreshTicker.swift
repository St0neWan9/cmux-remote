import Foundation

/// Owns a cancellable foreground observation cadence for snapshot-only chat APIs.
@MainActor
final class RefreshTicker {
    private var timer: Timer?
    func start() -> AsyncStream<Void> {
        stop()
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in stream.continuation.yield(()) }
        stream.continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.stop() } }
        return stream.stream
    }
    func stop() { timer?.invalidate(); timer = nil }
}
