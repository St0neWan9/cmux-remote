import Foundation
import Testing
@testable import TermRemoteMac

@Suite struct MacStaleResidentStopperTests {
    private func stateRoot(withLegacy: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stopper-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("term-remote"), withIntermediateDirectories: true)
        if withLegacy { try FileManager.default.createDirectory(at: root.appendingPathComponent("cmux-remote"), withIntermediateDirectories: true) }
        return root
    }

    @Test func theLegacyStopperMatchesOnlyTheOldHelperForTheOldDirectory() throws {
        let root = try stateRoot(withLegacy: true)
        let legacy = try #require(MacStaleResidentStopper.legacy(of: root.appendingPathComponent("term-remote")))
        let old = root.appendingPathComponent("cmux-remote").path
        let new = root.appendingPathComponent("term-remote").path
        #expect(legacy.matches(command: Substring("/Applications/CmuxRemote.app/Contents/Helpers/cmux-remote resident --state " + old)))
        // The replacement itself, a resident on the new directory, and cmux are never matched.
        #expect(!legacy.matches(command: Substring("/Applications/TermRemote.app/Contents/Helpers/term-remote resident --state " + new)))
        #expect(!legacy.matches(command: Substring("/Applications/CmuxRemote.app/Contents/Helpers/cmux-remote resident --state " + new)))
        #expect(!legacy.matches(command: Substring("/Applications/cmux.app/Contents/MacOS/cmux")))
        #expect(!legacy.matches(command: Substring("/Applications/CmuxRemote.app/Contents/Helpers/cmux-remote serve --state " + old)))
    }

    @Test func onlyTheDefaultDirectoryWithAPredecessorHasALegacyResident() throws {
        let withLegacy = try stateRoot(withLegacy: true)
        let without = try stateRoot(withLegacy: false)
        #expect(MacStaleResidentStopper.legacy(of: without.appendingPathComponent("term-remote")) == nil)
        // A custom --state path is never mapped to another directory.
        #expect(MacStaleResidentStopper.legacy(of: withLegacy.appendingPathComponent("cmux-remote")) == nil)
        #expect(MacStaleResidentStopper.legacy(of: withLegacy.appendingPathComponent("custom")) == nil)
    }

    @Test func theStaleStopperMatchesBothHelperNamesForItsOwnDirectory() throws {
        let directory = try stateRoot(withLegacy: false).appendingPathComponent("term-remote")
        let stopper = MacStaleResidentStopper(directory: directory)
        #expect(stopper.matches(command: Substring("/Applications/TermRemote.app/Contents/Helpers/term-remote resident --state " + directory.path)))
        #expect(stopper.matches(command: Substring("/Applications/CmuxRemote.app/Contents/Helpers/cmux-remote resident --state " + directory.path)))
        #expect(!stopper.matches(command: Substring("/Applications/TermRemote.app/Contents/Helpers/term-remote resident --state " + directory.path + "-other")))
    }

    @Test(.timeLimit(.minutes(1))) func aRunningOldResidentIsStopped() async throws {
        let root = try stateRoot(withLegacy: true)
        let helpers = root.appendingPathComponent("CmuxRemote.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let helper = helpers.appendingPathComponent("cmux-remote")
        try Data("#!/bin/sh\nwhile :; do sleep 1; done\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let old = Process()
        old.executableURL = helper
        old.arguments = ["resident", "--state", root.appendingPathComponent("cmux-remote").path]
        try old.run()
        defer { if old.isRunning { old.terminate() } }
        let legacy = try #require(MacStaleResidentStopper.legacy(of: root.appendingPathComponent("term-remote")))
        #expect(try await legacy.stop())
        old.waitUntilExit()
        #expect(!old.isRunning)
    }

    @Test func nothingRunningReportsNothingStopped() async throws {
        let root = try stateRoot(withLegacy: true)
        let legacy = try #require(MacStaleResidentStopper.legacy(of: root.appendingPathComponent("term-remote")))
        #expect(try await legacy.stop() == false)
        // Finding nothing must not touch the old directory, not even its lock file.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cmux-remote/serve.lock").path))
    }
}
