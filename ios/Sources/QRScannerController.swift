import UIKit
import AVFoundation

/// Camera resources remain main-actor owned; the capture delegate reports only one QR.
///
/// The page draws a viewfinder so the reader can tell where to aim, focuses where they tap, and answers a read
/// with a green frame and a haptic before it hands the code on — a camera preview alone gave no sign of whether
/// the code had been seen at all.
@MainActor
final class QRScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let onCode: @MainActor (String) -> Void
    private var layer: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private var consumed = false
    private var stopped = false
    /// Everything below sits over the preview: the dimmed surround, the frame, its brackets and the hint.
    private let dim = CAShapeLayer()
    private let frame = CAShapeLayer()
    private let brackets = CAShapeLayer()
    private let hint = UILabel()
    private let reticle = UIView()
    init(onCode: @escaping @MainActor (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .white
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !stopped else { return }
            guard granted else { showUnavailable(); return }
            configure()
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { showUnavailable(); return }
        device = camera
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { showUnavailable(); return }
        capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: capture); preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview); layer = preview
        focusWithoutTapping()
        addViewfinder()
        // A dedicated serial capture executor avoids blocking the UI during startup.
        CameraSessionWorker(session: capture).start()
    }
    /// Continuous autofocus from the start, so pointing the phone is enough; a tap refines it.
    private func focusWithoutTapping() {
        guard let device, device.isFocusModeSupported(.continuousAutoFocus) else { return }
        try? device.lockForConfiguration(); device.focusMode = .continuousAutoFocus; try? device.unlockForConfiguration()
    }
    private func addViewfinder() {
        dim.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        dim.fillRule = .evenOdd
        view.layer.addSublayer(dim)
        frame.strokeColor = UIColor.white.cgColor; frame.fillColor = UIColor.clear.cgColor
        frame.lineWidth = 2.5; frame.lineCap = .round
        view.layer.addSublayer(frame)
        brackets.strokeColor = UIColor.white.cgColor; brackets.fillColor = UIColor.clear.cgColor
        brackets.lineWidth = 4; brackets.lineCap = .round
        view.layer.addSublayer(brackets)
        hint.text = String(localized: "pair.camera_hint")
        hint.accessibilityIdentifier = "pair.camera_hint"
        hint.textColor = .white
        hint.font = .preferredFont(forTextStyle: .subheadline)
        hint.adjustsFontForContentSizeCategory = true
        hint.numberOfLines = 0; hint.textAlignment = .center
        hint.layer.shadowColor = UIColor.black.cgColor; hint.layer.shadowOpacity = 0.5
        hint.layer.shadowRadius = 3; hint.layer.shadowOffset = CGSize(width: 0, height: 1)
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        reticle.isUserInteractionEnabled = false
        reticle.layer.borderColor = UIColor.white.cgColor; reticle.layer.borderWidth = 1.5
        reticle.layer.cornerRadius = 12; reticle.isHidden = true
        view.addSubview(reticle)
        layoutViewfinder()
    }
    /// The square the reader aims at: centred, a little above the middle so the hint sits under it.
    private var spotlight: CGRect {
        let side = min(view.bounds.width, view.bounds.height) * 0.62
        return CGRect(x: (view.bounds.width - side) / 2, y: (view.bounds.height - side) / 2 - view.bounds.height * 0.06,
                      width: side, height: side)
    }
    private func layoutViewfinder() {
        guard view.bounds.width > 0 else { return }
        let hole = spotlight
        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(roundedRect: hole, cornerRadius: 22))
        dim.path = path.cgPath
        frame.path = UIBezierPath(roundedRect: hole, cornerRadius: 22).cgPath
        // Four corner brackets drawn by hand: a rounded rect's own corners are too soft to read as a viewfinder.
        let corner: CGFloat = 42, inset: CGFloat = 0
        let bracketsPath = UIBezierPath()
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: hole.minX + inset, y: hole.minY + corner), CGPoint(x: hole.minX + inset, y: hole.minY + inset), CGPoint(x: hole.minX + corner, y: hole.minY + inset)),
            (CGPoint(x: hole.maxX - corner, y: hole.minY + inset), CGPoint(x: hole.maxX - inset, y: hole.minY + inset), CGPoint(x: hole.maxX - inset, y: hole.minY + corner)),
            (CGPoint(x: hole.maxX - inset, y: hole.maxY - corner), CGPoint(x: hole.maxX - inset, y: hole.maxY - inset), CGPoint(x: hole.maxX - corner, y: hole.maxY - inset)),
            (CGPoint(x: hole.minX + corner, y: hole.maxY - inset), CGPoint(x: hole.minX + inset, y: hole.maxY - inset), CGPoint(x: hole.minX + inset, y: hole.maxY - corner)),
        ]
        for (start, middle, end) in corners {
            bracketsPath.move(to: start); bracketsPath.addLine(to: middle); bracketsPath.addLine(to: end)
        }
        brackets.path = bracketsPath.cgPath
        hint.frame = CGRect(x: MobileDesign.pageInset, y: hole.maxY + 20, width: view.bounds.width - MobileDesign.pageInset * 2,
                            height: hint.sizeThatFits(CGSize(width: view.bounds.width - MobileDesign.pageInset * 2, height: .greatestFiniteMagnitude)).height)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); layer?.frame = view.bounds; layoutViewfinder()
    }
    /// A tap focuses where it lands, then hands focus back to the continuous mode so moving on still focuses.
    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        guard let device, let layer, !stopped else { return }
        let point = gesture.location(in: view)
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
        guard device.isFocusPointOfInterestSupported else { return }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
            try device.unlockForConfiguration()
        } catch { return }
        showReticle(at: point)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.stopped, let device = self.device, device.isFocusModeSupported(.continuousAutoFocus) else { return }
            try? device.lockForConfiguration(); device.focusMode = .continuousAutoFocus; try? device.unlockForConfiguration()
        }
    }
    private func showReticle(at point: CGPoint) {
        reticle.isHidden = false
        reticle.frame = CGRect(x: point.x - 35, y: point.y - 35, width: 70, height: 70)
        reticle.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        UIView.animate(withDuration: 0.25) { self.reticle.transform = .identity }
        UIView.animate(withDuration: 0.4, delay: 0.7, options: []) { self.reticle.alpha = 0 } completion: { _ in
            self.reticle.isHidden = true; self.reticle.alpha = 1
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !stopped, !consumed, let value = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        consumed = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // The reader sees what the camera saw before the page goes away; the code is handed on a moment later.
        frame.strokeColor = UIColor.systemGreen.cgColor
        brackets.strokeColor = UIColor.systemGreen.cgColor
        hint.text = String(localized: "pair.camera_detected")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.stopped else { return }
            self.stop(); self.onCode(value)
        }
    }
    func stop() { stopped = true; CameraSessionWorker(session: capture).stop() }
    private func showUnavailable() {
        let label = UILabel(); label.text = String(localized: "pair.camera_unavailable"); label.textColor = .secondaryLabel; label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0; label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.centerYAnchor.constraint(equalTo: view.centerYAnchor), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: MobileDesign.pageInset), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -MobileDesign.pageInset)])
    }
}
