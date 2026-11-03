import Foundation
import CmuxRemoteCore

/// The shell line that starts a fixed agent with an optional first message.
/// The message is one quoted argument: it can never become a command, option or subcommand.
struct AgentCommandLine: Sendable {
    static let promptLimit = 4096

    /// Rejects a message that cannot be passed safely or is too long; nil or blank means no message.
    func validatedPrompt(_ prompt: String?) throws -> String? {
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard prompt.utf8.count <= Self.promptLimit, !prompt.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw BridgeError("invalid_input", "Enter a first message within the size limit.")
        }
        return prompt
    }

    func line(_ agent: LaunchAgent, prompt: String?) -> String {
        guard let prompt else { return agent.command }
        return agent.command + " " + quoted(argument(prompt))
    }

    /// A single word could name a subcommand (`codex login`) and a leading dash an option; a leading space is neither.
    func argument(_ prompt: String) -> String {
        prompt.hasPrefix("-") || !prompt.contains(where: \.isWhitespace) ? " " + prompt : prompt
    }

    /// POSIX single quotes when the text is printable on one line; otherwise ANSI-C `$'…'` quoting (zsh, bash, ksh),
    /// so a typed line never continues onto a second prompt line.
    func quoted(_ text: String) -> String {
        let plain = text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f }
        if plain { return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var result = "$'"
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7f { result += String(format: "\\x%02x", scalar.value) }
                else { result.unicodeScalars.append(scalar) }
            }
        }
        return result + "'"
    }
}
