import Foundation
import CmuxRemoteCore

/// What one Mac is waiting on the reader for, as the conversation list's reminder shows it.
struct PendingFeed: Equatable, Sendable {
    let count: Int
    /// The oldest pending item's title, the one the reader is most likely to need first.
    let firstTitle: String?

    init(count: Int, firstTitle: String?) { self.count = count; self.firstTitle = firstTitle }

    /// Reads the feed's items; only those still waiting for a reply count.
    init(items: [JSONValue]) {
        let waiting = items.filter { $0["status"].string == "pending" }
        count = waiting.count
        firstTitle = waiting.first.map { $0["title"].string ?? $0["tool_name"].string ?? String(localized: "feed.event") }
    }

    /// Several Macs' reminders as one, in Mac order.
    static func combined(_ feeds: [PendingFeed]) -> PendingFeed {
        PendingFeed(count: feeds.reduce(0) { $0 + $1.count }, firstTitle: feeds.first { $0.count > 0 }?.firstTitle)
    }
}
