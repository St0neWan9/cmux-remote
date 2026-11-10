import Foundation

/// The stretch of a conversation's timeline the page lays out.
///
/// The page lays its rows out in a plain stack, measured whole, rather than in a lazy one. A lazy stack guesses the
/// height of every row it has not built, and a conversation's rows range from one line to several screens: when a
/// running group collapsed under a new reply, the guess for the rows out of sight flipped between two values on
/// every layout pass, the bottom anchor chased it, and the page sat blank between its header and composer for as
/// long as the conversation stayed open. A measured stack has nothing to guess, so it is kept to the newest rows
/// and grows a page at a time as the reader reads back.
public struct TimelineWindow: Equatable, Sendable {
    /// Rows laid out when the page opens, and kept once the reader is back at the newest one.
    public static let opening = 40
    /// Rows added each time the reader reaches the top of what is laid out.
    public static let page = 30
    /// Past this many rows, a reader at the newest one goes back to the opening stretch.
    public static let limit = 120
    /// The first row laid out; nil lays out the newest `opening` rows, whatever they are.
    public private(set) var start: String?
    public init(start: String? = nil) { self.start = start }
    /// The rows laid out, as positions in the timeline's ids. A first row the timeline no longer has (a rewritten
    /// transcript) falls back to the newest rows.
    public func range(in ids: [String]) -> Range<Int> {
        range(count: ids.count) { ids.firstIndex(of: $0) }
    }
    /// The same range for a timeline that is not a list of ids, so a page evaluated often need not build one.
    public func range(count: Int, index: (String) -> Int?) -> Range<Int> {
        if let start, let found = index(start) { return found..<count }
        return max(0, count - Self.opening)..<count
    }
    /// Whether rows already held lie above the ones laid out.
    public func hidesEarlier(in ids: [String]) -> Bool { range(in: ids).lowerBound > 0 }
    /// Lays out one more page of rows already held. False when every held row is laid out already, which is when
    /// the conversation itself has to read further back.
    public mutating func extend(in ids: [String]) -> Bool {
        let lower = range(in: ids).lowerBound
        guard lower > 0 else { return false }
        start = ids[max(0, lower - Self.page)]
        return true
    }
    /// Lays out from the first row held, after an earlier page of the conversation arrived above it.
    public mutating func showFromFirst(in ids: [String]) { start = ids.first }
    /// Holds the first row in place while the reader is away from the newest one: new rows arriving below must
    /// not push it out from above the reader.
    public mutating func pin(in ids: [String]) {
        guard start == nil || !ids.contains(start!) else { return }
        let lower = range(in: ids).lowerBound
        start = lower < ids.count ? ids[lower] : nil
    }
    /// Back at the newest row: a stretch grown past the limit returns to the opening one. Nothing the reader sees
    /// moves, since the page rests at its end and the rows dropped are far above it.
    public mutating func settle(in ids: [String]) {
        guard start != nil, range(in: ids).count > Self.limit else { return }
        start = nil
    }
}
