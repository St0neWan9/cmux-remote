import SwiftUI
import CoreImage.CIFilterBuiltins

/// A real encoded bootstrap QR with a white quiet zone in both appearance modes.
///
/// The enrollment payload grows with every shared space, and a dense code rendered at
/// 200 points leaves under two points per module. Tapping opens a larger copy so a
/// phone camera can resolve it.
struct PairingQRCodeView: View {
    let link: String
    private let design = MacDesignTokens()
    @State private var expanded = false

    var body: some View {
        if let image = qrImage {
            Button { expanded = true } label: { code(image, size: design.qrCodeSize) }
                .buttonStyle(.plain)
                .help(String(localized: "mac.pairing.enlarge", bundle: .interface))
                .sheet(isPresented: $expanded) {
                    VStack(spacing: 20) {
                        code(image, size: 560)
                        Text(String(localized: "mac.pairing.largeHint", bundle: .interface))
                            .foregroundStyle(.secondary)
                        Button(String(localized: "mac.cancel", bundle: .interface)) { expanded = false }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(32)
                    .background(.white)
                }
        }
    }

    private func code(_ image: CGImage, size: CGFloat) -> some View {
        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
            .frame(width: size, height: size).padding(design.qrQuietZone).background(.white)
            .accessibilityHidden(false)
            .accessibilityLabel(String(localized: "mac.pairing.qr", bundle: .interface))
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
