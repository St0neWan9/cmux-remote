import Foundation
import CmuxRemoteCore

/// Reads only an explicitly user-selected security-scoped image file.
struct ImageFileLoader: Sendable {
    func load(_ url: URL) async throws -> Data {
        let task = Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw BridgeError("invalid_image", "Select an image file.", status: 422) }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                var data = Data()
                while true {
                    try Task.checkCancellation()
                    guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else { break }
                    guard data.count + chunk.count <= 33_554_432 else { throw BridgeError("too_large", "The selected file is too large.", status: 413) }
                    data.append(chunk)
                }
                return data
            } catch let error as BridgeError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw BridgeError("image_load_failed", "The selected image file could not be read.", status: 422) }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
