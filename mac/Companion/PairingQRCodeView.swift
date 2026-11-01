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
        // The generator emits one white module around the code. Cropping it leaves the view's own padding as the
        // only quiet zone, so the code's visible square starts exactly where the view's frame does.
        let ink = output.extent.insetBy(dx: 1, dy: 1)
        let enlarged = output.cropped(to: ink).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        return CIContext().createCGImage(enlarged, from: enlarged.extent)
    }
}
