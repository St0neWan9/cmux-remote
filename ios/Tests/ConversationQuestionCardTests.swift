import XCTest
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat
@testable import CmuxRemote

/// What a conversation knows about the questions its agent is waiting on.
///
/// The card comes from the transcript and its answer from the Feed, so the page's knowledge lags the card. A
/// failed Feed read says nothing about whether a request is still waiting: treating it as "no questions" made a
/// live card read "cannot be answered here" the moment a relay link dropped.
@MainActor
final class ConversationQuestionCardTests: XCTestCase {
    private let generation = "G1"
    private let prompt = "用哪个方案?"
    private let descriptor = SessionDescriptor(id: "s1", agent: "claude", title: "Conversation", cwd: nil,
                                               workspaceID: "w1", surfaceID: "surf1", state: "idle")

    private func message(_ seq: Int) -> ChatMessage {
        ChatMessage(id: "m\(seq)", seq: seq, role: .agent, timestamp: Date(timeIntervalSinceReferenceDate: 0),
                    kind: .prose(ChatProse(text: "m\(seq)")))
    }
    private func question(_ seq: Int, prompt: String) -> ChatMessage {
        ChatMessage(id: "q\(seq)", seq: seq, role: .agent, timestamp: Date(timeIntervalSinceReferenceDate: 0),
                    kind: .question(ChatQuestion(prompt: prompt, options: [.init(label: "快速方案"), .init(label: "稳妥方案")])))
    }
    private func page(_ messages: [ChatMessage]) -> ConversationArchivePage {
        ConversationArchivePage(snapshot: ConversationSnapshot(messages: messages, hasMore: false,
                                                               generation: generation, clipped: false),
                                nextCursor: nil, complete: true)
    }
    /// The Feed's own item for a pending request naming this conversation's agent and session.
    private var feedItem: JSONValue {
        let workstream = "cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data(descriptor.id.utf8).base64EncodedString()
        return .object(["kind": .string("question"), "status": .string("pending"), "request_id": .string("r1"),
                        "workstream_id": .string(workstream),
                        "questions": .array([.object([
                            "id": .string("q0"), "prompt": .string(prompt), "multi_select": .bool(false),
                            "allow_custom": .bool(false), "allow_skip": .bool(false),
                            "options": .array([.object(["id": .string("1"), "label": .string("快速方案")]),
                                               .object(["id": .string("2"), "label": .string("稳妥方案")])])])])
                       ])
    }
    private final class Pages: @unchecked Sendable {
        private let lock = NSLock()
        private var page: ConversationArchivePage
        init(_ page: ConversationArchivePage) { self.page = page }
        func replace(_ page: ConversationArchivePage) { lock.lock(); self.page = page; lock.unlock() }
        var current: ConversationArchivePage { lock.lock(); defer { lock.unlock() }; return page }
    }
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [JSONValue]?
        private var reads = 0
        init(_ items: [JSONValue]?) { self.items = items }
        /// nil stands for a read that failed: the link dropped before the Feed answered.
        func replace(_ items: [JSONValue]?) { lock.lock(); self.items = items; lock.unlock() }
        var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
        func read() throws -> [JSONValue] {
            lock.lock(); defer { lock.unlock() }
            reads += 1
            guard let items else { throw BridgeError("link_unavailable", "The link is down.", status: 503) }
            return items
        }
    }
    private func makeModel(_ pages: Pages, feed: Feed) throws -> ConversationModel {
        let pairing = try PairingConfiguration(host: "127.0.0.1", port: 1, token: String(repeating: "a", count: 64),
                                               certificateSHA256: String(repeating: "b", count: 64))
        let descriptor = descriptor
        return ConversationModel(session: descriptor, client: RemoteClient(pairing: pairing),
                                 loadRecovery: { nil }, saveRecovery: { _ in },
                                 readSessions: { [descriptor] },
                                 readPreview: { PreviewSnapshot(text: nil, available: false) },
                                 readFeed: { try feed.read() },
                                 archive: ArchiveChain { _, _ in pages.current })
    }

    func testAPendingQuestionIsOfferedToItsCard() async throws {
        let pages = Pages(page([message(1), question(2, prompt: prompt)]))
        let feed = Feed([feedItem])
        let model = try makeModel(pages, feed: feed)
        await model.refresh()
        XCTAssertEqual(model.pendingQuestions[prompt]?.requestID, "r1", "The waiting question was not offered to its card")
        XCTAssertTrue(model.questionsVerified)
    }
    func testAQuestionStaysAnswerableWhenTheFeedReadFails() async throws {
        let pages = Pages(page([message(1), question(2, prompt: prompt)]))
        let feed = Feed([feedItem])
        let model = try makeModel(pages, feed: feed)
        await model.refresh()
        XCTAssertNotNil(model.pendingQuestions[prompt])
        // The link drops while the agent is still waiting. A new card appears, which reads the Feed at once.
        feed.replace(nil)
        pages.replace(page([message(1), question(2, prompt: prompt), question(3, prompt: "第二个问题?")]))
        await model.refresh()
        XCTAssertFalse(model.questionsVerified, "A failed read was reported as an answer")
        XCTAssertEqual(model.pendingQuestions[prompt]?.requestID, "r1",
                       "A failed Feed read threw away the request its card was answering")
    }
    func testACardIsNotCalledUnavailableBeforeAnyFeedReadAnswers() async throws {
        let pages = Pages(page([message(1), question(2, prompt: prompt)]))
        let feed = Feed(nil)
        let model = try makeModel(pages, feed: feed)
        await model.refresh()
        XCTAssertFalse(model.questionsVerified, "A page that never read the Feed claimed to know there is no request")
        XCTAssertTrue(model.pendingQuestions.isEmpty)
    }
    func testANewQuestionCardReadsTheFeedWithoutWaitingOutTheInterval() async throws {
        let pages = Pages(page([message(1)]))
        let feed = Feed([])
        let model = try makeModel(pages, feed: feed)
        await model.refresh(); await model.refresh()
        XCTAssertEqual(feed.readCount, 1, "A quiet page read the Feed on every refresh")
        pages.replace(page([message(1), question(2, prompt: prompt)]))
        await model.refresh()
        XCTAssertEqual(feed.readCount, 2, "A card that just appeared waited out the Feed's interval before it could be answered")
    }
}
