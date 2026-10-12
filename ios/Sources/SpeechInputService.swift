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
        let permission = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        try Task.checkCancellation(); guard generation == identity else { throw CancellationError() }
        guard permission == .authorized else { throw BridgeError("speech_permission", "Speech permission was denied.", status: 403) }
        let microphone = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation(); guard generation == identity else { throw CancellationError() }
        guard microphone else { throw BridgeError("speech_permission", "Microphone permission was denied.", status: 403) }
        guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw unavailable() }
        let stream = AsyncThrowingStream<SpeechInputResult, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in Task { @MainActor in if self?.generation == identity { self?.cancel() } } }
        do {
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers); try audio.setActive(true); audioActive = true
            let engine = AVAudioEngine(); let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = true
            self.engine = engine; self.request = request
            let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw unavailable() }
            let sink = SpeechAudioSink(request: request)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }; tapped = true
            self.recognizer = recognizer
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let value = result.map { SpeechInputResult(text: $0.bestTranscription.formattedString, isFinal: $0.isFinal) }
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.generation == identity else { return }
                    if let value { self.continuation?.yield(value); if value.isFinal { self.continuation?.finish(); self.cancel(); return } }
                    if failed { self.continuation?.finish(throwing: self.unavailable()); self.cancel() }
                }
            }
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
}
#endif
