import SwiftUI
import AVFoundation

/// UIKit owns camera capture; only decoded strings cross into the pairing view.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { QRScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) { controller.stop() }
}
