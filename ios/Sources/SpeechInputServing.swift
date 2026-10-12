import Foundation

/// Speech is a local draft source; this interface has no conversation or send operation.
@MainActor protocol SpeechInputServing: AnyObject {
    func start() async throws -> AsyncThrowingStream<SpeechInputResult, any Error>
    func finish()
    func cancel()
}
