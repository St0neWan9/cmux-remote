import SwiftUI
import CoreImage.CIFilterBuiltins

/// A real encoded bootstrap QR with a white quiet zone in both appearance modes.
struct PairingQRCodeView: View {
    let link: String
    private let design = MacDesignTokens()
    var body: some View {
        if let image = qrImage {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                .frame(width: design.qrCodeSize, height: design.qrCodeSize).padding(design.qrQuietZone).background(.white)
                .accessibilityHidden(false)
                .accessibilityLabel(String(localized: "mac.pairing.qr", bundle: .interface))
        }
    }
    private var qrImage: CGImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(link.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        return CIContext().createCGImage(enlarged, from: enlarged.extent)
    }
}
