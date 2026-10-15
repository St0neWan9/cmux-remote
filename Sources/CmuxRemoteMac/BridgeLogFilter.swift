import Foundation
import CmuxRemoteBridge

/// The level and keyword a reader narrows the Bridge log to; it never changes the file.
public struct BridgeLogFilter: Sendable, Equatable {
    public enum Threshold: String, CaseIterable, Sendable {
        /// Every line, including debug lines and lines without a recognised level.
        case all
        /// Info, warning and error lines.
        case info
        /// Only warning and error lines.
        case warning
    }
    public var threshold: Threshold
    /// Matched case-insensitively anywhere in the line; surrounding whitespace is ignored and an empty keyword matches every line.
    public var keyword: String
    public init(threshold: Threshold = .all, keyword: String = "") { self.threshold = threshold; self.keyword = keyword }
    public func apply(_ lines: [BridgeLogLine]) -> [BridgeLogLine] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.filter { line in
            admits(line.level) && (needle.isEmpty || line.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }
    private func admits(_ level: BridgeLog.Level?) -> Bool {
        switch threshold {
        case .all: return true
        case .info: return level == .info || level == .warning || level == .error
        case .warning: return level == .warning || level == .error
        }
    }
}
