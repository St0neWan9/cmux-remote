import Foundation
import Testing
import CmuxRemoteBridge
import CmuxRemoteCore
import CmuxRemoteMac

@Suite struct BridgeLogTailTests {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func line(_ index: Int, _ level: String = "INFO") -> String {
        "2026-10-15T13:40:12.305+08:00 " + level + " [relay] event " + String(format: "%05d", index)
    }
    func write(_ lines: [String], to url: URL, trailing: String = "") throws {
        try Data((lines.map { $0 + "\n" }.joined() + trailing).utf8).write(to: url)
    }
    @Test func readsOnlyCompleteLinesInsideTheByteBound() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let written = (0..<3_000).map { line($0) }
        // The Bridge may be in the middle of writing the last line; it must not be shown in part.
        try write(written, to: BridgeLogTail.file(in: directory), trailing: "2026-10-15T13:40:13.000+08:00 ERR")
        let budget = 10_000
        let lines = try #require(try BridgeLogTail(byteLimit: budget).read(directory: directory))
        #expect(lines.last?.text == written.last)
        #expect(lines.allSatisfy { written.contains($0.text) }, "a line cut by the byte bound was shown")
        #expect(lines.map(\.text) == Array(written.suffix(lines.count)))
        let lineBytes = written[0].utf8.count + 1
        #expect(lines.count == budget / lineBytes)
        #expect(lines.reduce(0) { $0 + $1.text.utf8.count + 1 } <= budget)
    }
    @Test func aLineStartingExactlyAtTheBoundIsKept() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let written = (0..<10).map { line($0) }
        try write(written, to: BridgeLogTail.file(in: directory))
        let lineBytes = written[0].utf8.count + 1
        let lines = try #require(try BridgeLogTail(byteLimit: lineBytes * 3).read(directory: directory))
        #expect(lines.map(\.text) == Array(written.suffix(3)))
    }
    @Test func continuesIntoTheRotatedFileInOrderUntilTheLineLimit() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let current = BridgeLogTail.file(in: directory)
        let older = (0..<5).map { line($0, "WARNING") }, newer = (5..<8).map { line($0) }
        try write(older, to: current.appendingPathExtension("1"))
        try write(newer, to: current)
        #expect(try BridgeLogTail().read(directory: directory)?.map(\.text) == older + newer)
        #expect(try BridgeLogTail(lineLimit: 4).read(directory: directory)?.map(\.text) == Array((older + newer).suffix(4)))
        // A current file that fills the byte bound by itself leaves nothing to read from the rotated file.
        let newerBytes = newer.reduce(0) { $0 + $1.utf8.count + 1 }
        #expect(try BridgeLogTail(byteLimit: newerBytes).read(directory: directory)?.map(\.text) == newer)
        // Right after a rotation only the rotated file has content.
        try FileManager.default.removeItem(at: current)
        #expect(try BridgeLogTail().read(directory: directory)?.map(\.text) == older)
    }
    @Test func aMissingLogIsDistinctFromAnEmptyOne() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try BridgeLogTail().read(directory: directory) == nil)
        try Data().write(to: BridgeLogTail.file(in: directory))
        #expect(try BridgeLogTail().read(directory: directory) == [])
    }
    @Test func anUnreadableLogReportsAStableCode() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = BridgeLogTail.file(in: directory)
        try write([line(0)], to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(throws: BridgeError("log_unreadable", "The Bridge log cannot be read.")) { try BridgeLogTail().read(directory: directory) }
    }
    @Test func levelFilterKeepsContinuationLinesWithTheirMessage() throws {
        let lines = BridgeLogLine.parse([
            line(0, "DEBUG"), line(1, "INFO"), line(2, "WARNING"), "  continuation of the warning", line(3, "ERROR"), line(4, "INFO") + " Relay Connected",
        ])
        #expect(lines.map(\.level) == [.debug, .info, .warning, .warning, .error, .info])
        #expect(BridgeLogFilter(threshold: .all).apply(lines).count == 6)
        #expect(BridgeLogFilter(threshold: .info).apply(lines).map(\.id) == [1, 2, 3, 4, 5])
        #expect(BridgeLogFilter(threshold: .warning).apply(lines).map(\.id) == [2, 3, 4])
        #expect(BridgeLogFilter(threshold: .all, keyword: "  relay connected ").apply(lines).map(\.id) == [5])
        #expect(BridgeLogFilter(threshold: .warning, keyword: "relay connected").apply(lines).isEmpty)
    }
}
