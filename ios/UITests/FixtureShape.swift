import Foundation

/// Which transcript the isolated fixture was started with.
///
/// The fixture picks its transcript from an empty flag file in its state directory, and a UI test's own
/// environment is not inherited by the runner under `xcodebuild test-without-building`, so asking
/// `ProcessInfo` for a flag always came back empty and every shape-gated test silently skipped. The pairing
/// file sits in that same state directory, so the test reads the flags from where the fixture actually reads
/// them: one file per shape, next to `phone.json`.
enum FixtureShape {
    /// The names a fixture state directory may carry; a run picks exactly one.
    static let names = ["short-conversation", "tall-reply", "long-conversation", "awaiting-question", "resumable-session"]
    /// The shape this run's fixture holds, read from the directory of the pairing file the runner passed.
    static func current(environment variables: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let pairing = variables["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairing.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: pairing).deletingLastPathComponent()
        return names.first { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }
}
