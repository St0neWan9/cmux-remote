import Foundation
import Observation
import CmuxRemoteCore

/// Owns dictation and bounded deadlines; confirmed text is returned to the ordinary composer.
@MainActor @Observable final class SpeechDraftModel {
    enum State { case idle, starting, recording, finishing }
    private(set) var state = State.idle
    private(set) var text = ""
    private(set) var error: String?
    var active: Bool { state != .idle }
    private let input: any SpeechInputServing
    private let delay: @Sendable (Duration) async throws -> Void
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    init(input: any SpeechInputServing, delay: @escaping @Sendable (Duration) async throws -> Void = { try await ContinuousClock().sleep(for: $0) }) { self.input = input; self.delay = delay }
    func start() async {
        guard !active, !Task.isCancelled else { return }
        cancel(); let request = generation; state = .starting; error = nil
        let operation = Task { @MainActor [self] in
            defer { if generation == request { state = .idle; deadline?.cancel(); deadline = nil; input.cancel() } }
            do {
                let results = try await input.start()
                guard generation == request, !Task.isCancelled else { return }
                state = .recording
                deadline = Task { @MainActor [self] in
                    do { try await delay(.seconds(60)); guard generation == request, !Task.isCancelled else { return }; finish() } catch {}
                }
                for try await result in results {
                    guard generation == request, !Task.isCancelled else { return }
                    guard result.text.utf8.count <= 8192 else { throw BridgeError("speech_too_long", "The dictated draft exceeds its limit.", status: 422) }
                    text = result.text
                    if result.isFinal { break }
                }
                if generation == request, !Task.isCancelled, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = String(localized: "voice.no_speech") }
            } catch { if generation == request, !Task.isCancelled { self.error = ErrorPresentation().message(error) } }
        }
        task = operation
        await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        if generation == request { task = nil }
    }
    func finish() {
        guard state == .recording else { return }
        state = .finishing; input.finish(); deadline?.cancel()
        let request = generation
        deadline = Task { @MainActor [self] in
            do {
                try await delay(.seconds(5)); guard generation == request, !Task.isCancelled else { return }
                let retained = text; cancel(); text = retained
                if retained.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = String(localized: "voice.no_speech") }
            } catch {}
        }
    }
    func suspend() { let retained = text; cancel(); text = retained }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; deadline?.cancel(); deadline = nil; input.cancel(); state = .idle; text = ""; error = nil }
    /// Confirmation stops audio and yields text; it never dispatches a prompt.
    func takeText() -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }; cancel(); return value
    }
}
