import Foundation

/// When an activity group may open inside the timeline instead of on its own page.
///
/// A running Agent's group grows by the second. Expanded inline it is one row that SwiftUI lays out in full, so a
/// long run turned scrolling into a stutter; past the limit the group stays a summary row that keeps counting and
/// opens its own page instead.
public enum ActivityGroupPolicy {
    public static let inlineLimit = 5
    public static func showsInline(operationCount: Int, isLatest: Bool, choice: Bool?) -> Bool {
        guard operationCount <= inlineLimit else { return false }
        return choice ?? isLatest
    }
}
