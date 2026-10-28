import Foundation

/// A conversation title as the phone may set it: one line of plain text, bounded, and empty to clear it.
///
/// The title lands in cmux's own tab model, so it is validated here rather than in the UI: a terminal tab has no
/// room for line breaks or control characters, and a name longer than this is not a name.
public enum SessionTitle {
    public static let limit = 120
    public static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= limit else { throw BridgeError("invalid_input", "Use a title of at most \(limit) characters.", status: 422) }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw BridgeError("invalid_input", "A title cannot contain line breaks or control characters.", status: 422)
        }
        return trimmed
    }
}
