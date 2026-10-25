import XCTest
import CmuxRemoteCore
@testable import CmuxRemote

/// Reopening a task's page shows the stored copy before the read that confirms it.
final class BackgroundTaskCacheTests: XCTestCase {
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func testASavedTaskComesBackWithItsCursor() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BackgroundTaskCache(directory: directory)
        let entry = BackgroundTaskCache.Entry(snapshot: nil, text: "line 1\nline 2\n", loadedBytes: 14, nextOffset: 14,
                                              totalBytes: 14, running: true, storedAt: Date())
        await cache.save(entry, scope: "mac", sessionID: "session-1", taskID: "toolu_1")
        let loaded = await cache.load(scope: "mac", sessionID: "session-1", taskID: "toolu_1")
        XCTAssertEqual(loaded?.text, entry.text)
        XCTAssertEqual(loaded?.nextOffset, 14)
        XCTAssertEqual(loaded?.running, true)
    }
    /// Two Macs, two conversations and two tasks never collide, and nothing escapes the directory.
    func testIdentifiersStayApart() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BackgroundTaskCache(directory: directory)
        let first = BackgroundTaskCache.Entry(snapshot: nil, text: "a", loadedBytes: 1, nextOffset: nil, totalBytes: 1, running: false, storedAt: Date())
        let second = BackgroundTaskCache.Entry(snapshot: nil, text: "b", loadedBytes: 1, nextOffset: nil, totalBytes: 1, running: false, storedAt: Date())
        await cache.save(first, scope: "mac", sessionID: "s", taskID: "../t")
        await cache.save(second, scope: "mac", sessionID: "s", taskID: "t")
        let escaped = await cache.load(scope: "mac", sessionID: "s", taskID: "../t")
        let direct = await cache.load(scope: "mac", sessionID: "s", taskID: "t")
        XCTAssertEqual(escaped?.text, "a")
        XCTAssertEqual(direct?.text, "b")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { !$0.contains("/") && $0.hasSuffix(".json") })
    }
    func testAnOversizedCopyIsNotSaved() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BackgroundTaskCache(directory: directory)
        let huge = BackgroundTaskCache.Entry(snapshot: nil, text: String(repeating: "x", count: 4_500_000), loadedBytes: 4_500_000,
                                             nextOffset: nil, totalBytes: 4_500_000, running: false, storedAt: Date())
        await cache.save(huge, scope: "mac", sessionID: "s", taskID: "t")
        let loaded = await cache.load(scope: "mac", sessionID: "s", taskID: "t")
        XCTAssertNil(loaded)
    }
}
