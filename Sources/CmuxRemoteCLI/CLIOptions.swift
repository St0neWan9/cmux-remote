/// Minimal explicit options for the first command-line interface.
struct CLIOptions {
    let args: [String]
    func value(_ name: String) -> String? {
        guard let index = args.firstIndex(of: "--" + name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    func contains(_ name: String) -> Bool { args.contains("--" + name) }
}
