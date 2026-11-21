import Foundation

/// Extracts Antigravity CLI's queued user prompts from rendered terminal screen rows.
///
/// While a turn is running and prompts are waiting in Antigravity's input queue, `agy` renders
/// queued prompt lines above the composer accompanied by `Press <key> to edit queued messages`.
/// Only the bottom screen window is inspected so scrollback prose mentioning queued messages
/// never triggers a false positive.
public struct AntigravityQueuedScreenExtractor: Sendable {
    public struct Extraction: Sendable, Equatable {
        public let hasQueueHint: Bool
        public let prompts: [String]
    }

    private static let maxPrompts = 32
    private static let maxPromptCharacters = 2_048

    public init() {}

    public func extract(lines: [String]) -> Extraction {
        let rows = lines.map(Self.trimTrailing)
        let nonEmpty = rows.indices.filter { !rows[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty else { return Extraction(hasQueueHint: false, prompts: []) }

        // Queued message hints only appear near the composer at the bottom of the terminal.
        let searchWindow = Set(nonEmpty.suffix(25))
        guard let hintIndex = rows.indices.reversed().first(where: { index in
            searchWindow.contains(index) && Self.isQueuedEditHint(rows[index])
        }) else {
            return Extraction(hasQueueHint: false, prompts: [])
        }

        let lowerBound = max(0, hintIndex - 40)
        var rawLines: [String] = []
        var cursor = hintIndex - 1
        while cursor >= lowerBound {
            let row = rows[cursor]
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !rawLines.isEmpty { break }
                cursor -= 1
                continue
            }
            if Self.isDivider(trimmed)
                || AntigravityProseScreenExtractor.isBrailleStatusLine(row)
                || Self.isTranscriptBoundary(trimmed) {
                break
            }
            rawLines.append(row)
            cursor -= 1
        }
        rawLines.reverse()

        var prompts: [String] = []
        for row in rawLines {
            if let stripped = Self.stripBulletPrefix(row) {
                if !stripped.isEmpty {
                    prompts.append(Self.bounded(stripped))
                }
            } else {
                let continuation = row.trimmingCharacters(in: .whitespaces)
                guard !continuation.isEmpty else { continue }
                if let last = prompts.popLast() {
                    prompts.append(Self.bounded(last + " " + continuation))
                } else {
                    prompts.append(Self.bounded(continuation))
                }
            }
            if prompts.count >= Self.maxPrompts { break }
        }
        return Extraction(hasQueueHint: true, prompts: prompts)
    }

    static func isQueuedEditHint(_ row: String) -> Bool {
        let lower = row.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasPrefix("press ") && lower.contains("to edit queued messages")
    }

    private static func stripBulletPrefix(_ row: String) -> String? {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        for prefix in ["> ", ">\u{00a0}", "› ", "❯ ", "• ", "↳ ", "→ ", "◦ ", "▪ "] {
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func isDivider(_ trimmed: String) -> Bool {
        guard trimmed.count >= 8 else { return false }
        return trimmed.unicodeScalars.allSatisfy { (0x2500...0x257f).contains($0.value) }
    }

    private static func isTranscriptBoundary(_ trimmed: String) -> Bool {
        guard let first = trimmed.first else { return false }
        if ["●", "○", "⏺", "⎿"].contains(first) { return true }
        if trimmed.hasPrefix("… ") && trimmed.hasSuffix("…") { return true }
        return false
    }

    private static func trimTrailing(_ row: String) -> String {
        var scalars = Array(row.unicodeScalars)
        while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func bounded(_ text: String) -> String {
        guard text.unicodeScalars.count > maxPromptCharacters else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxPromptCharacters)))
    }
}
