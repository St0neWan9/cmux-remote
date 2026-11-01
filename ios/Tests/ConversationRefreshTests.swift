import XCTest
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat
@testable import CmuxRemote

/// What a conversation's refresh does with the pages the Bridge hands it.
///
/// A page read from the newest end is asked for again on every change. When a turn records more than one page
/// between two reads, nothing else would ever ask for the stretch in between, so the page's own cursor is walked
/// back to the newest message on screen. These checks pin that behaviour and the reads a refresh spends.
@MainActor
final class ConversationRefreshTests: XCTestCase {
    private let generation = "G1"
    private let descriptor = SessionDescriptor(id: "s1", agent: "claude", title: "Conversation", cwd: nil,
                                               workspaceID: "w1", surfaceID: "surf1", state: "idle")
    private func message(_ seq: Int) -> ChatMessage {
        ChatMessage(id: "m\(seq)", seq: seq, role: .agent, timestamp: Date(timeIntervalSinceReferenceDate: 0),
                    kind: .prose(ChatProse(text: "m\(seq)")))
    }
    private func page(_ seqs: [Int], cursor: String?, hasMore: Bool = true) -> ConversationArchivePage {
        ConversationArchivePage(snapshot: ConversationSnapshot(messages: seqs.map(message), hasMore: hasMore,
                                                               generation: generation, clipped: false), nextCursor: cursor,
                                complete: !hasMore)
    }
    /// One archive whose pages the test swaps between refreshes, standing for the same conversation moments later.
    private final class Archive: @unchecked Sendable {
        private let lock = NSLock()
        private var pages: [String?: ConversationArchivePage]
        init(_ pages: [String?: ConversationArchivePage]) { self.pages = pages }
        func replace(_ pages: [String?: ConversationArchivePage]) { lock.lock(); self.pages = pages; lock.unlock() }
        func page(_ cursor: String?) -> ConversationArchivePage? { lock.lock(); defer { lock.unlock() }; return pages[cursor] }
    }
    private final class Listing: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private func makeModel(_ archive: Archive, listings: Listing = Listing(), previews: Listing = Listing()) throws -> ConversationModel {
        let pairing = try PairingConfiguration(host: "127.0.0.1", port: 1, token: String(repeating: "a", count: 64),
                                               certificateSHA256: String(repeating: "b", count: 64))
        let descriptor = descriptor
        return ConversationModel(session: descriptor, client: RemoteClient(pairing: pairing),
                                 loadRecovery: { nil }, saveRecovery: { _ in },
                                 readSessions: { listings.increment(); return [descriptor] },
                                 readPreview: { previews.increment(); return PreviewSnapshot(text: nil, available: false) },
                                 readFeed: { [] },
                                 archive: ArchiveChain { cursor, _ in
                                     guard let page = archive.page(cursor) else {
                                         throw BridgeError("history_unavailable", "No such page in this test.", status: 404)
                                     }
                                     return page
                                 })
    }

    func testABurstThatOutranOnePageIsReadBackToTheMessageOnScreen() async throws {
        let archive = Archive([nil: page([100, 200, 300], cursor: "c0")])
        let model = try makeModel(archive)
        await model.refresh()
        XCTAssertEqual(model.messages.map(\.seq), [100, 200, 300])
        // The next read starts at the newest end again, three pages above what is on screen.
        archive.replace([nil: page([1000, 1100, 1200], cursor: "c1"),
                         "c1": page([400, 500, 600], cursor: "c2"),
                         "c2": page([700, 800, 900], cursor: "c3")])
        await model.refresh()
        XCTAssertEqual(model.messages.map(\.seq), [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200],
                       "The stretch between the page and the messages on screen was never read")
    }
    func testAPageThatOverlapsWhatIsOnScreenIsNotWalkedFurtherBack() async throws {
        let archive = Archive([nil: page([100, 200, 300], cursor: "c0")])
        let model = try makeModel(archive)
        await model.refresh()
        // c1 names a page the reader never asked for: a page that overlaps must not walk into it.
        archive.replace([nil: page([300, 400, 500], cursor: "c1"), "c1": page([100, 200], cursor: nil)])
        await model.refresh()
        XCTAssertEqual(model.messages.map(\.seq), [100, 200, 300, 400, 500])
    }
    func testAHiddenConversationReadsOnlyItsTranscript() async throws {
        let archive = Archive([nil: page([100], cursor: nil)])
        let listings = Listing(), previews = Listing()
        let model = try makeModel(archive, listings: listings, previews: previews)
        await model.syncHidden()
        XCTAssertEqual(model.messages.map(\.seq), [100], "The hidden conversation did not read its transcript")
        XCTAssertEqual(listings.value, 0, "A hidden conversation read the Mac's whole session list")
        XCTAssertEqual(previews.value, 0, "A hidden conversation read the live tail it does not draw")
        // On screen it reads everything again.
        await model.refresh()
        XCTAssertEqual(listings.value, 1, "An on-screen conversation did not read its own row")
        XCTAssertEqual(previews.value, 1, "An on-screen conversation did not read its live tail")
    }
    func testARefreshReadsTheSessionListOnlyOnceForItsBurst() async throws {
        let archive = Archive([nil: page([100], cursor: nil)])
        let listings = Listing()
        let model = try makeModel(archive, listings: listings)
        await model.refresh(); await model.refresh(); await model.refresh()
        XCTAssertEqual(listings.value, 1, "Every refresh read the whole Mac's session list again")
    }
}
