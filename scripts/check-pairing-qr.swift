import Foundation
import CoreGraphics
import Vision

// Validate the actual terminal QR renderer without printing or persisting its credential payload.
let state = CommandLine.arguments[1]
let process = Process(); let output = Pipe()
process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/debug/cmux-remote")
process.arguments = ["pairing", "--state", state, "--host", "127.0.0.1", "--port", "7759"]
process.standardOutput = output; try process.run()
let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
let text = String(decoding: data, as: UTF8.self)
guard let start = text.range(of: "\u{001B}[30;47m"), let end = text.range(of: "\u{001B}[0m", range: start.upperBound..<text.endIndex) else { fatalError("No terminal QR output") }
let rows = text[start.upperBound..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
let width = rows[0].count; let height = rows.count * 2; let scale = 8
var pixels = [UInt8](repeating: 255, count: width * height * scale * scale * 4)
for (rowIndex, row) in rows.enumerated() {
    for (column, value) in row.enumerated() {
        for half in 0..<2 {
            let dark = value == "█" || (half == 0 && value == "▀") || (half == 1 && value == "▄")
            for y in 0..<scale { for x in 0..<scale {
                let index = (((rowIndex * 2 + half) * scale + y) * width * scale + column * scale + x) * 4
                pixels[index] = dark ? 0 : 255; pixels[index + 1] = pixels[index]; pixels[index + 2] = pixels[index]; pixels[index + 3] = 255
            } }
        }
    }
}
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let image = CGImage(width: width * scale, height: height * scale, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * scale * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
try VNImageRequestHandler(cgImage: image).perform([request])
guard let result = request.results?.first?.payloadStringValue, result.hasPrefix("cmux-remote://pair?v=1&payload=") else { fatalError("Rendered QR did not decode") }
print("Terminal QR decoded successfully; credential contents were not displayed.")
