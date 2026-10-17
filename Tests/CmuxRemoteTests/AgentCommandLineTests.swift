import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct AgentCommandLineTests {
    /// The fixed flags the program always carries, before any message.
    private var fixedFlags: [String] { Array(LaunchAgent.claude.command.split(separator: " ").dropFirst().map(String.init)) }
    /// Runs the line with `printf` in place of the agent, so the shell itself shows what the agent would receive.
    private func received(_ prompt: String, shell: String) throws -> [String] {
        let commandLine = AgentCommandLine()
        let line = commandLine.line(.claude, prompt: prompt)
        #expect(line.hasPrefix("claude "))
        let probe = "printf '%s\\0'" + line.dropFirst("claude".count)
        let process = Process(); process.executableURL = URL(fileURLWithPath: shell); process.arguments = ["-c", probe]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    @Test func aMessageIsAlwaysExactlyOneLiteralArgument() throws {
        let hostile = [
            "fix the build", "it's done; rm -rf ~", "$(touch /tmp/agent-command-line-pwned)", "`id` and $HOME and ${PATH}",
            "line one\nline two\ttabbed", "back\\slash 'quote' \"double\"", "emoji 👩‍💻 and 中文", "a\u{1b}[31m red\u{7f}", "\"; exit 1; \"",
        ]
        for shell in ["/bin/sh", "/bin/zsh", "/bin/bash"] where FileManager.default.isExecutableFile(atPath: shell) {
            for prompt in hostile {
                let got = try received(prompt, shell: shell)
                // The program's own flags come first; the message must still arrive as exactly one literal argument.
                #expect(got == fixedFlags + [prompt], "\(shell) changed \(prompt.debugDescription) into \(got.debugDescription) via \(AgentCommandLine().line(.claude, prompt: prompt).debugDescription)")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: "/tmp/agent-command-line-pwned"))
    }

    @Test func aMessageNeverBecomesASubcommandOrOption() throws {
        // `codex login` or `claude update` would run a subcommand; `-p` an option. A leading space prevents both.
        for prompt in ["login", "update", "-p", "--dangerously-skip-permissions", "-"] {
            let argument = try received(prompt, shell: "/bin/sh")
            #expect(argument == fixedFlags + [" " + prompt])
        }
        #expect(try received("update the readme", shell: "/bin/sh") == fixedFlags + ["update the readme"])
    }

    @Test func aMultiLineMessageIsTypedAsOneLine() {
        let line = AgentCommandLine().line(.codex, prompt: "first\nsecond")
        #expect(!line.contains("\n") && !line.contains("\r"))
        #expect(line == "codex --no-daemon $'first\\nsecond'")
    }

    @Test func blankOversizedAndNulMessagesAreRejectedOrDropped() throws {
        let commandLine = AgentCommandLine()
        #expect(try commandLine.validatedPrompt(nil) == nil)
        #expect(try commandLine.validatedPrompt(" \n\t") == nil)
        #expect(throws: BridgeError.self) { try commandLine.validatedPrompt(String(repeating: "x", count: AgentCommandLine.promptLimit + 1)) }
        #expect(throws: BridgeError.self) { try commandLine.validatedPrompt("a\u{0}b") }
        #expect(commandLine.line(.claude, prompt: nil) == LaunchAgent.claude.command)
    }
}
