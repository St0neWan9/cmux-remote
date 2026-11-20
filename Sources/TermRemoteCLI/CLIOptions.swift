/// Minimal explicit options for the first command-line interface.
struct CLIOptions {
    let args: [String]
    func value(_ name: String) -> String? {
        guard let index = args.firstIndex(of: "--" + name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    func values(_ name: String) -> [String] {
        args.indices.compactMap { args[$0] == "--" + name && $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func contains(_ name: String) -> Bool { args.contains("--" + name) }
}
