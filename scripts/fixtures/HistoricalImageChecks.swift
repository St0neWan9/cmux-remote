import Foundation
import CmuxRemoteCore

private actor HeldHistoryImage {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var held: CheckedContinuation<Data, any Error>?
    func read() async throws -> Data { try await withCheckedThrowingContinuation { held = $0; started.continuation.yield(()) } }
    func finish(_ bytes: Data) { held?.resume(returning: bytes); held = nil }
}

struct HistoricalImageChecks {
    @MainActor static func run() async throws -> (count: Int, failures: [String]) {
        var count = 0; var failures: [String] = []
        func check(_ value: Bool, _ message: String) { count += 1; if !value { failures.append(message) } }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
        let payload = try await ImageAttachmentEncoder().encode(png, name: "fixture.png")
        let jpeg = Data(base64Encoded: payload.dataBase64)!
        let reference = ConversationImageReference(id: String(repeating: "a", count: 64), messageID: "image", generation: "generation", name: "Image.jpg", requiresProjectRead: false)
        let image = HistoricalImageModel(reference: reference, fetch: { jpeg }); await image.load()
        check(image.data == jpeg && image.error == nil && !image.loading, "A valid recorded JPEG preview did not load")
        for invalid in [Data("<html>error</html>".utf8), Data(repeating:0,count:524_289), png] {
            let bad = HistoricalImageModel(reference: reference, fetch: { invalid }); await bad.load()
            check(bad.data == nil && bad.error != nil && !bad.loading, "An invalid or oversized image response was presented")
        }
        let held = HeldHistoryImage(); let suspended = HistoricalImageModel(reference: reference, fetch: { try await held.read() })
        let loading = Task { @MainActor in await suspended.load() }
        var started = held.started.stream.makeAsyncIterator(); _ = await started.next()
        suspended.suspend(); await held.finish(jpeg); await loading.value
        check(suspended.data == nil && !suspended.loading, "A suspended historical-image read published late bytes")
        let revoked = HistoricalImageModel(reference: reference, fetch: { throw BridgeError("scope_denied", "Revoked", status:403) }); await revoked.load()
        check(revoked.data == nil && revoked.error != nil, "A revoked image read hid its error")
        return (count, failures)
    }
}
