import Foundation
import CmuxRemoteCore

/// The id lookups a timeline needs, built once per change rather than once per body evaluation.
///
/// Scrolling re-evaluates the page body, and with thousands of messages rebuilding three dictionaries over the
/// whole conversation on every frame is what made reading back feel heavy. The maps depend only on which
/// messages, responses and images exist, so one build per change is enough.
final class TimelineIndexCache {
    struct Index {
        let firstResponse: [String: ConversationResponse]
        let lastResponse: [String: ConversationResponse]
        let imagesByMessage: [String: [ConversationImageReference]]
    }
    private final class Box: NSObject { let index: Index; init(_ index: Index) { self.index = index } }
    nonisolated(unsafe) static let shared = TimelineIndexCache()
    private let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>(); cache.countLimit = 4; return cache
    }()
    func index(key: String, build: () -> Index) -> Index {
        let key = key as NSString
        if let cached = cache.object(forKey: key) { return cached.index }
        let index = build()
        cache.setObject(Box(index), forKey: key)
        return index
    }
}
