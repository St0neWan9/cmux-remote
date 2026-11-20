import Foundation

/// Supplies the intentional metadata snapshot cadence where cmux has no topology subscription.
struct MirrorTopologyTicker: Sendable {
    func start() -> AsyncStream<Void> {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    try Task.checkCancellation(); stream.continuation.yield(())
                }
            } catch {}
            stream.continuation.finish()
        }
        stream.continuation.onTermination = { _ in task.cancel() }
        return stream.stream
    }
}
