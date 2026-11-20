import Foundation
import CoreImage

/// Renders the pairing link locally; the resulting QR is a credential and is never logged by serve.
struct TerminalQRCode {
    func render(_ text: String) throws -> String {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw QRFailure.unavailable }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { throw QRFailure.unavailable }
        let size = Int(image.extent.width)
        var pixels = [UInt8](repeating: 255, count: size * size)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(image, toBitmap: &pixels, rowBytes: size, bounds: image.extent, format: .L8, colorSpace: nil)
        let border = 4; let width = size + border * 2
        func dark(_ x: Int, _ y: Int) -> Bool {
            guard x >= border, x < size + border, y >= border, y < size + border else { return false }
            return pixels[(size - 1 - (y - border)) * size + (x - border)] < 128
        }
        var rows: [String] = []
        for y in stride(from: 0, to: width, by: 2) {
            var row = ""
            for x in 0..<width {
                switch (dark(x, y), dark(x, y + 1)) {
                case (true, true): row += "█"
                case (true, false): row += "▀"
                case (false, true): row += "▄"
                case (false, false): row += " "
                }
            }
            rows.append(row)
        }
        return "\u{001B}[30;47m" + rows.joined(separator: "\n") + "\u{001B}[0m"
    }
    private enum QRFailure: Error { case unavailable }
}
