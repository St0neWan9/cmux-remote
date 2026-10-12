import Foundation
import ImageIO
import Observation
import CmuxRemoteCore

/// Owns a single bounded image read, with the same navigation/background cancellation policy as text.
@MainActor @Observable final class HistoricalImageModel {
    let reference: ConversationImageReference
    private(set) var data: Data?
    private(set) var loading = false
    private(set) var error: String?
    private let reads = ReadRequestOwner()
    private let fetch: @Sendable () async throws -> Data
    init(reference: ConversationImageReference, fetch: @escaping @Sendable () async throws -> Data) { self.reference = reference; self.fetch = fetch }
    func suspend() { reads.suspend(); loading = false }
    func load() async {
        await reads.run { [self] request in
            loading = true
            defer { if reads.revision == request { loading = false } }
            do {
                let bytes = try await fetch()
                guard reads.isCurrent(request) else { return }
                guard !bytes.isEmpty, bytes.count <= 524_288,
                      let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetType(source) as String? == "public.jpeg", CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 1600, height <= 1600 else { throw BridgeError("image_unavailable", "The preview is invalid.", status: 422) }
                data = bytes; error = nil
            } catch { if reads.isCurrent(request) { data = nil; self.error = ErrorPresentation().message(error) } }
        }
    }
}
