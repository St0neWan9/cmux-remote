import Foundation

/// Holds every part of a generated VT snapshot until its final paint is complete.
public struct TerminalPresentationFrame: Sendable {
    /// Creates a stateless presentation framer.
    public init() {}

    /// Combines generated replay segments into one synchronized terminal update.
    ///
    /// Older producers can release synchronized output between their empty
    /// baseline and positioned paint. DEC synchronization is not nested, so an
    /// outer begin alone does not prevent that intermediate publication.
    /// - Parameter replay: Validated, generated VT bytes, rather than raw PTY output.
    /// - Returns: The replay with one final synchronized-output release.
    public func bytes(for replay: Data) -> Data {
        let begin = Data("\u{1B}[?2026h".utf8), end = Data("\u{1B}[?2026l".utf8)
        var result = begin, offset = replay.startIndex
        while let release = replay.range(of: end, in: offset..<replay.endIndex) {
            result.append(replay[offset..<release.lowerBound])
            offset = release.upperBound
        }
        result.append(replay[offset..<replay.endIndex])
        result.append(end)
        return result
    }
}
