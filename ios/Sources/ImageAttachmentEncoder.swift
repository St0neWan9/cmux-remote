import Foundation
import ImageIO
import UniformTypeIdentifiers
import CmuxRemoteCore

/// Downsample off the UI actor and strip source metadata before upload.
struct ImageAttachmentEncoder: Sendable {
    func encode(_ data: Data, name: String) async throws -> ChatImagePayload {
        let task = Task.detached(priority: .userInitiated) {
            guard data.count <= 33_554_432, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else { throw BridgeError("invalid_image", "This image cannot be loaded.", status: 422) }
            // Four images fit the existing 1 MiB wire envelope, including base64.
            for size in [1600, 1200, 800, 400] {
                try Task.checkCancellation()
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                               kCGImageSourceCreateThumbnailWithTransform: true,
                                               kCGImageSourceThumbnailMaxPixelSize: size,
                                               kCGImageSourceShouldCacheImmediately: true]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw BridgeError("invalid_image", "This image cannot be decoded.", status: 422) }
                for quality in [0.85, 0.65, 0.45, 0.25] {
                    try Task.checkCancellation()
                    let output = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw BridgeError("invalid_image", "This image cannot be prepared.", status: 422) }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                    if CGImageDestinationFinalize(destination), output.length <= 131_072 {
                        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
                            .filter { !$0.isNewline && $0 != "\0" && $0 != "\\" }
                        let limited = String(decoding: base.utf8.prefix(230), as: UTF8.self)
                        return ChatImagePayload(fileName: (limited.isEmpty ? "Image" : limited) + ".jpg", format: "jpeg", data: output as Data)
                    }
                }
            }
            throw BridgeError("too_large", "This image exceeds the upload limit after resizing.", status: 413)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
