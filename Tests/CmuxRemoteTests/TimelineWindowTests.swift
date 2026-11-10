import Testing
@testable import CmuxRemoteCore

@Suite struct TimelineWindowTests {
    private func ids(_ range: ClosedRange<Int>) -> [String] { range.map { "m\($0)" } }

    /// A conversation restored whole lays out only its newest rows, however much of it the phone holds.
    @Test func aLongConversationOpensOnItsNewestRows() {
        let window = TimelineWindow()
        let all = ids(1...3000)
        #expect(window.range(in: all) == (3000 - TimelineWindow.opening)..<3000)
        #expect(window.hidesEarlier(in: all))
        #expect(window.range(in: ids(1...12)) == 0..<12)
        #expect(!window.hidesEarlier(in: ids(1...12)))
    }
    /// Reaching the top lays out a page of the rows already held before the conversation reads any further back.
    @Test func readingBackGrowsAPageAtATime() {
        var window = TimelineWindow()
        let all = ids(1...100)
        let first = window.extend(in: all)
        #expect(first)
        #expect(window.range(in: all).count == TimelineWindow.opening + TimelineWindow.page)
        let second = window.extend(in: all)
        #expect(second)
        #expect(window.range(in: all) == 0..<100)
        let third = window.extend(in: all)
        #expect(!third)
    }
    /// An earlier page read from the Mac lands above the rows laid out, and is shown at once.
    @Test func anEarlierPageIsShownWhenItArrives() {
        var window = TimelineWindow()
        var all = ids(41...60)
        let extended = window.extend(in: all)
        #expect(!extended)
        all = ids(1...60)
        window.showFromFirst(in: all)
        #expect(window.range(in: all) == 0..<60)
    }
    /// A reader away from the newest row keeps the rows above them while new rows arrive below.
    @Test func newRowsDoNotPushThePinnedTopAway() {
        var window = TimelineWindow()
        var all = ids(1...50)
        window.pin(in: all)
        let first = window.range(in: all).lowerBound
        all += ids(51...70)
        #expect(window.range(in: all).lowerBound == first)
        // Without the pin the newest stretch would have moved down under the reader.
        #expect(TimelineWindow().range(in: all).lowerBound > first)
    }
    /// Back at the newest row, a stretch grown past the limit returns to the opening one; a smaller one stays.
    @Test func settlingTrimsOnlyAStretchPastTheLimit() {
        var window = TimelineWindow(start: "m1")
        let all = ids(1...(TimelineWindow.limit + 10))
        window.settle(in: all)
        #expect(window.range(in: all).count == TimelineWindow.opening)
        var small = TimelineWindow(start: "m1")
        small.settle(in: ids(1...60))
        #expect(small.range(in: ids(1...60)) == 0..<60)
    }
    /// A rewritten transcript has none of the rows the window started from; the newest rows are laid out.
    @Test func aReplacedTranscriptFallsBackToTheNewestRows() {
        let window = TimelineWindow(start: "old")
        let all = ids(1...90)
        #expect(window.range(in: all) == (90 - TimelineWindow.opening)..<90)
    }
}
