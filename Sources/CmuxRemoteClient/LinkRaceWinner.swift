import Foundation

/// The path that authenticated first while the LAN and the relay are dialled together, so the other path's
/// cancellation reads as a lost race instead of a failure.
final class LinkRaceWinner: @unchecked Sendable {
    enum Path: String, Sendable { case lan, relay }
    private let lock = NSLock()
    private var first: Path?
    /// Records `path` as the winner unless the other path already won.
    func claim(_ path: Path) { lock.withLock { if first == nil { first = path } } }
    /// The path that won, once one has.
    var path: Path? { lock.withLock { first } }
}
