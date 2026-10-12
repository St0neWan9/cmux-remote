import Foundation
import ImageIO
import CmuxRemoteCore

/// Decode bounded static images before a fixed existing-session chat RPC can run.
struct ChatImagePolicy {
    static let maximumImageBytes = 524_288
    static let maximumTotalBytes = 655_360
    func attachments(_ images: [ChatImagePayload]) throws -> [JSONValue] {
        guard images.count <= 4, Set(images.map(\.id)).count == images.count else { throw invalid() }
        var total = 0
        return try images.map { image in
            guard ["png", "jpeg"].contains(image.format), !image.fileName.isEmpty, image.fileName.utf8.count <= 255,
                  !image.fileName.contains("/"), !image.fileName.contains("\\"), !image.fileName.contains("\0"),
                  image.dataBase64.utf8.count <= (Self.maximumImageBytes + 2) / 3 * 4,
                  let data = Data(base64Encoded: image.dataBase64), !data.isEmpty,
                  data.count <= Self.maximumImageBytes else { throw invalid() }
            total += data.count
            guard total <= Self.maximumTotalBytes else { throw BridgeError("too_large", "The selected images exceed the combined upload limit.", status: 413) }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  let type = CGImageSourceGetType(source) as String?, type == (image.format == "png" ? "public.png" : "public.jpeg"),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 8_388_608,
                  CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { throw invalid() }
            return .object(["data_b64": .string(image.dataBase64), "format": .string(image.format)])
        }
    }
    private func invalid() -> BridgeError { BridgeError("invalid_image", "Select up to four valid PNG or JPEG images within the upload limits.", status: 422) }
}
