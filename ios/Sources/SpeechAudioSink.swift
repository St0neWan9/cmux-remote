#if os(iOS)
import Speech
import AVFAudio

/// Apple's real-time request accepts tap buffers concurrently with its recognition consumer.
/// The immutable request is the only object accessed by the audio callback; lifecycle stays on MainActor.
final class SpeechAudioSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
}
#endif
