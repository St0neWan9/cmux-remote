import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

@MainActor private final class FixtureSpeechInput: SpeechInputServing {
    let started = AsyncStream<Void>.makeStream()
    let results = AsyncThrowingStream<SpeechInputResult, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
    var failure: String?
    var holdPermission = false
    private var permission: CheckedContinuation<Void, Never>?
    var finishCalls = 0
    var starts = 0
    func start() async throws -> AsyncThrowingStream<SpeechInputResult, any Error> {
        starts += 1; started.continuation.yield(())
        if holdPermission { await withCheckedContinuation { permission = $0 } }
        if let failure { throw BridgeError(failure, "Fixture speech unavailable", status:403) }
        return results.stream
    }
    func releasePermission() { permission?.resume(); permission = nil }
    func finish() { finishCalls += 1 }
    func cancel() { if starts > 0 { results.continuation.finish() } }
    func emit(_ text: String, final: Bool = false) { results.continuation.yield(SpeechInputResult(text:text,isFinal:final)); if final { results.continuation.finish() } }
}
private actor VoiceDeadlineFixture {
    nonisolated let started = AsyncStream<Int64>.makeStream()
    private var waiting: [UUID:(Int64,CheckedContinuation<Void,any Error>)] = [:]
    func wait(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { waiting[id] = (duration.components.seconds, $0); started.continuation.yield(duration.components.seconds) }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) { waiting.removeValue(forKey:id)?.1.resume(throwing:CancellationError()) }
    func release(_ seconds: Int64) { for id in waiting.filter({ $0.value.0 == seconds }).keys { waiting.removeValue(forKey:id)?.1.resume() } }
}
private actor VoiceSendFixture {
    var calls = 0
    func send(_ value: SendRequest) -> MutationReceipt { calls += 1; return MutationReceipt(operationID:value.operationID,accepted:true) }
}

struct SpeechStateChecks {
    @MainActor private static func partial(_ text: String, input: FixtureSpeechInput, model: SpeechDraftModel) async -> Bool {
        let observed = AsyncStream<Void>.makeStream()
        withObservationTracking({ _ = model.text }, onChange: { observed.continuation.yield(()); observed.continuation.finish() })
        let timeout = Task { try? await ContinuousClock().sleep(for:.seconds(2)); observed.continuation.finish() }
        defer { timeout.cancel() }
        input.emit(text)
        var changes = observed.stream.makeAsyncIterator(); _ = await changes.next()
        return model.text == text
    }
    @MainActor static func run(client: RemoteClient) async -> (count:Int, failures:[String]) {
        var count = 0; var failures:[String] = []
        func check(_ value:Bool,_ message:String) { count += 1; if !value { failures.append(message) } }
        for code in ["speech_permission", "speech_unavailable"] {
            let source = FixtureSpeechInput(); source.failure = code
            let model = SpeechDraftModel(input:source); await model.start()
            check(!model.active && model.text.isEmpty && model.error != nil, "Denied/unavailable dictation appeared to record or hid its error")
        }
        let source = FixtureSpeechInput(); let model = SpeechDraftModel(input:source)
        let recording = Task { @MainActor in await model.start() }
        var start = source.started.stream.makeAsyncIterator(); _ = await start.next()
        check(await partial("Partial draft", input:source, model:model), "Partial dictation did not replace the utterance preview")
        model.finish(); source.emit("Final dictated draft", final:true); await recording.value
        check(!model.active && model.text == "Final dictated draft" && model.error == nil && source.finishCalls == 1, "Final speech did not stop audio while retaining its draft")
        check(model.takeText() == "Final dictated draft" && model.text.isEmpty, "Explicit use did not return and release dictated text")
        let late = FixtureSpeechInput(); late.holdPermission = true
        let cancelled = SpeechDraftModel(input:late); let permission = Task { @MainActor in await cancelled.start() }
        var permissionStart = late.started.stream.makeAsyncIterator(); _ = await permissionStart.next()
        cancelled.cancel(); late.releasePermission(); await permission.value
        check(!cancelled.active && cancelled.text.isEmpty && cancelled.error == nil && late.finishCalls == 0, "Cancelled permission completion restarted dictation")
        let backgroundSource = FixtureSpeechInput(); let background = SpeechDraftModel(input:backgroundSource)
        let backgroundTask = Task { @MainActor in await background.start() }
        var backgroundStart = backgroundSource.started.stream.makeAsyncIterator(); _ = await backgroundStart.next()
        _ = await partial("Keep recognized words", input:backgroundSource, model:background)
        background.suspend(); backgroundSource.emit("Late words", final:true); await backgroundTask.value
        check(!background.active && background.text == "Keep recognized words", "Background cancellation erased recognized draft text or accepted late results")
        background.cancel(); check(background.text.isEmpty, "Explicit dictation cancellation retained discarded words")
        let oversizedSource = FixtureSpeechInput(); let oversized = SpeechDraftModel(input:oversizedSource)
        let oversizedTask = Task { @MainActor in await oversized.start() }
        var oversizedStart = oversizedSource.started.stream.makeAsyncIterator(); _ = await oversizedStart.next()
        oversizedSource.emit(String(repeating:"x",count:8193), final:true); await oversizedTask.value
        check(!oversized.active && oversized.text.isEmpty && oversized.error != nil, "Oversized speech output escaped the draft bound")
        let timer = VoiceDeadlineFixture(); let timeoutSource = FixtureSpeechInput()
        let timed = SpeechDraftModel(input:timeoutSource,delay:{ try await timer.wait($0) })
        let timedTask = Task { @MainActor in await timed.start() }
        var durations = timer.started.stream.makeAsyncIterator(); _ = await durations.next()
        _ = await partial("Retain on finalization timeout", input:timeoutSource, model:timed)
        timed.finish(); let finalWait = await durations.next()
        await timer.release(5); await timedTask.value
        check(finalWait == 5 && !timed.active && timed.text == "Retain on finalization timeout", "Finalization deadline abandoned partial words or kept the microphone active")
        let sender = VoiceSendFixture(); let composingSource = FixtureSpeechInput()
        let session = SessionDescriptor(id:"speech-draft",agent:"claude",title:"Speech",cwd:nil,workspaceID:"workspace",surfaceID:"surface",state:"idle")
        let conversation = ConversationModel(session:session,client:client,speechInput:composingSource,loadRecovery:{ nil },saveRecovery:{ _ in },sendRequest:{ await sender.send($0) })
        conversation.draft = "Keep typed text"
        let dictating = Task { @MainActor in await conversation.speech.start() }
        var composingStart = composingSource.started.stream.makeAsyncIterator(); _ = await composingStart.next()
        _ = await partial("Recognized words", input:composingSource, model:conversation.speech)
        await conversation.send()
        check(await sender.calls == 0 && conversation.draft == "Keep typed text", "Active dictation submitted or overwrote the typed draft")
        conversation.useSpeechDraft(); await dictating.value
        check(await sender.calls == 0 && conversation.draft == "Keep typed text\nRecognized words", "Using dictated words dispatched a prompt or erased existing text")
        return (count, failures)
    }
}
