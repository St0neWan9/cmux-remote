import Foundation
import Observation
import CmuxRemoteCore

/// Selected images remain local until an explicit send confirms their operation.
@MainActor @Observable
final class ImageDraftModel {
    var images: [ChatImagePayload] = []
    var loading = false
    var error: String?
    private var generation = 0
    func load(_ selections: [ImageSelection], encode: @Sendable (Data, String) async throws -> ChatImagePayload) async {
        guard !selections.isEmpty else { return }
        generation += 1; let current = generation; loading = false
        guard selections.count + images.count <= 4 else { error = String(localized: "error.image"); return }
        loading = true; error = nil
        defer { if generation == current { loading = false } }
        do {
            var prepared: [ChatImagePayload] = []
            for selection in selections {
                let data = try await selection.load()
                try Task.checkCancellation()
                guard generation == current else { return }
                prepared.append(try await encode(data, selection.name))
                try Task.checkCancellation()
                guard generation == current else { return }
            }
            images.append(contentsOf: prepared)
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            self.error = error is BridgeError ? ErrorPresentation().message(error) : String(localized: "error.image_load")
        }
    }
    func cancelLoading() { generation += 1; loading = false }
    func remove(_ id: UUID) { cancelLoading(); images.removeAll { $0.id == id }; error = nil }
    func removeSubmitted(_ ids: Set<UUID>) { images.removeAll { ids.contains($0.id) } }
}
