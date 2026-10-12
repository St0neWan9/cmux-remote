import UIKit
import AVFoundation

/// Camera resources remain main-actor owned; the capture delegate reports only one QR.
@MainActor
final class QRScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let onCode: @MainActor (String) -> Void
    private var layer: AVCaptureVideoPreviewLayer?
    private var consumed = false
    private var stopped = false
    init(onCode: @escaping @MainActor (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .white
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !stopped else { return }
            guard granted else { showUnavailable(); return }
            configure()
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { showUnavailable(); return }
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { showUnavailable(); return }
        capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: capture); preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview); layer = preview
        // A dedicated serial capture executor avoids blocking the UI during startup.
        let worker = CameraSessionWorker(session: capture)
        worker.start()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layer?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !stopped, !consumed, let value = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        consumed = true; stop(); onCode(value)
    }
    func stop() { stopped = true; CameraSessionWorker(session: capture).stop() }
    private func showUnavailable() {
        let label = UILabel(); label.text = String(localized: "pair.camera_unavailable"); label.textColor = .secondaryLabel; label.numberOfLines = 0; label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.centerYAnchor.constraint(equalTo: view.centerYAnchor), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)])
    }
}
