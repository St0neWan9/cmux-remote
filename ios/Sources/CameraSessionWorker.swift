import AVFoundation

/// AVCaptureSession start/stop have no async API; one shared capture queue owns those calls.
final class CameraSessionWorker: @unchecked Sendable {
    private static let captureQueue = DispatchQueue(label: "cmux-remote.camera")
    private let session: AVCaptureSession
    init(session: AVCaptureSession) { self.session = session }
    func start() { Self.captureQueue.async { [self] in session.startRunning() } }
    func stop() { Self.captureQueue.async { [self] in if session.isRunning { session.stopRunning() } } }
}
