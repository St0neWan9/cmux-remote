#if os(iOS)
import Foundation
import AVFAudio
import Speech
import CmuxRemoteCore

/// Native on-device speech only; unavailable locale/models never fall back to server recognition.
@MainActor final class SpeechInputService: SpeechInputServing {
    private let audio: AVAudioSession
    private let locale: Locale
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<SpeechInputResult, any Error>.Continuation?
    private var generation = UUID()
    private var tapped = false
    private var audioActive = false
    init(audio: AVAudioSession, locale: Locale) { self.audio = audio; self.locale = locale }
    func start() async throws -> AsyncThrowingStream<SpeechInputResult, any Error> {
        cancel(); let identity = generation
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw unavailable() }
        // Speech and microphone authorization complete on TCC's own queues. On iOS 26 a closure the
        // compiler treats as main-actor isolated traps there (dispatch_assert_queue_fail), which is
        // the mic-tap crash. Read a decided authorization synchronously and use the nonisolated async
        // request only when one permission has never been asked for.
        switch Self.resolvedAuthorization() {
        case .denied: throw permission()
        case .undetermined:
            guard await Self.requestAuthorization() else { throw permission() }
            try Task.checkCancellation(); guard generation == identity else { throw CancellationError() }
        case .granted: break
        }
        guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw unavailable() }
        let stream = AsyncThrowingStream<SpeechInputResult, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in Task { @MainActor in if self?.generation == identity { self?.cancel() } } }
        do {
            // `.duckOthers` is invalid with `.record` and makes the session fail to activate.
            try audio.setCategory(.record, mode: .measurement); try audio.setActive(true); audioActive = true
            let engine = AVAudioEngine(); let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = true
            self.engine = engine; self.request = request
            let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
            // An invalid format makes installTap raise an Obj-C exception that try/catch cannot trap.
            guard format.sampleRate > 0, format.channelCount > 0 else { throw unavailable() }
            let sink = SpeechAudioSink(request: request)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(sink: sink)); tapped = true
            self.recognizer = recognizer
            recognition = recognizer.recognitionTask(with: request, resultHandler: makeRecognitionHandler(identity: identity))
            engine.prepare(); try engine.start()
            return stream.stream
        } catch { cancel(); throw error }
    }
    func finish() { stopAudio(); request?.endAudio() }
    func cancel() {
        generation = UUID(); stopAudio(); request?.endAudio(); recognition?.cancel(); recognition = nil; recognizer = nil; request = nil
        continuation?.finish(); continuation = nil; engine = nil
    }
    private func stopAudio() {
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
        if audioActive { try? audio.setActive(false, options: .notifyOthersOnDeactivation); audioActive = false }
    }
    private func unavailable() -> BridgeError { BridgeError("speech_unavailable", "On-device speech recognition is unavailable.", status: 422) }
    private func permission() -> BridgeError { BridgeError("speech_permission", "Speech or microphone permission was denied.", status: 403) }

    /// Whether speech and microphone authorization are already decided. Only `undetermined` needs
    /// the async request, whose completion the system runs off the main actor.
    private enum Authorization { case granted, denied, undetermined }

    /// `nonisolated` and side-effect free: these are plain synchronous status reads, so asking never
    /// enters the completion path that traps off the main actor.
    private nonisolated static func resolvedAuthorization() -> Authorization {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        let decided: Bool
        switch microphone {
        case .granted, .denied: decided = true
        case .undetermined: decided = false
        @unknown default: decided = false
        }
        guard speech != .notDetermined, decided else { return .undetermined }
        return speech == .authorized && microphone == .granted ? .granted : .denied
    }

    /// `nonisolated` with a `@Sendable` completion on purpose: `SFSpeechRecognizer` and
    /// `AVFoundation` invoke their completion handlers on their own queues, and a main-actor closure
    /// called there traps under Swift 6.
    private nonisolated static func requestAuthorization() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// `nonisolated` so the block is not main-actor isolated: `installTap` runs it on the realtime
    /// audio render thread, where a main-actor closure traps. Appending is thread-safe on the request.
    private nonisolated static func makeTapBlock(sink: SpeechAudioSink) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in sink.append(buffer) }
    }

    /// `nonisolated` so the handler is not main-actor isolated: Speech delivers results on its own
    /// queue. It snapshots only `Sendable` values and hops to the main actor once.
    private nonisolated func makeRecognitionHandler(identity: UUID) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak self] result, error in
            let value = result.map { SpeechInputResult(text: $0.bestTranscription.formattedString, isFinal: $0.isFinal) }
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == identity else { return }
                if let value {
                    // A final result can arrive empty after partials already carried the words;
                    // yielding it would replace them with nothing.
                    if !value.text.isEmpty { self.continuation?.yield(value) }
                    if value.isFinal { self.continuation?.finish(); self.cancel() }
                    return
                }
                if failed { self.continuation?.finish(throwing: self.unavailable()); self.cancel() }
            }
        }
    }
}
#endif
