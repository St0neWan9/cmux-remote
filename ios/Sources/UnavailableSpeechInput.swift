import Foundation
import CmuxRemoteCore

/// Portable model tests and unsupported platforms never create a fake active recorder.
@MainActor final class UnavailableSpeechInput: SpeechInputServing {
    func start() async throws -> AsyncThrowingStream<SpeechInputResult, any Error> { throw BridgeError("speech_unavailable", "On-device speech recognition is unavailable.", status: 422) }
    func finish() {}
    func cancel() {}
}
