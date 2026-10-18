import Foundation

/// A model name that is safe to type into an agent's prompt as the argument of its model command.
///
/// Model ids and aliases are single tokens such as `opus`, `gpt-6-luna` or `provider/model-name[1m]`; anything
/// with spaces, quotes or control characters would become a different command, so it is refused.
public enum AgentModelName {
    public static func validated(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:/@+[]")
        guard (1...128).contains(name.utf8.count), name.unicodeScalars.allSatisfy(allowed.contains), name.first != "-" else {
            throw BridgeError("invalid_model", "Use a model name without spaces or special characters.")
        }
        return name
    }
}
