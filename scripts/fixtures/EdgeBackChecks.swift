import Foundation
import CoreGraphics

/// The drawer's "Add Mac" replaces the root view, so no navigation stack entry exists to pop and UIKit's
/// own edge recognizer never fires. The drag is judged by `EdgeBackSwipe` instead.
enum EdgeBackChecks {
    static func run() -> (count: Int, failures: [String]) {
        let swipe = EdgeBackSwipe()
        var failures: [String] = []
        var count = 0
        func check(_ condition: Bool, _ message: String) { count += 1; if !condition { failures.append(message) } }
        check(swipe.begins(at: CGPoint(x: 4, y: 300)), "A drag at the very edge must begin the swipe")
        check(swipe.begins(at: CGPoint(x: swipe.edge, y: 300)), "A drag on the edge boundary must begin the swipe")
        check(!swipe.begins(at: CGPoint(x: swipe.edge + 1, y: 300)), "A drag inside the page must not begin the swipe")
        check(!swipe.begins(at: CGPoint(x: -3, y: 300)), "A drag left of the screen must not begin the swipe")
        check(swipe.commits(CGSize(width: swipe.commit, height: 4)), "A long forward drag must complete the back")
        check(swipe.commits(CGSize(width: 260, height: 90)), "A fast diagonal drag with forward travel must complete the back")
        check(!swipe.commits(CGSize(width: swipe.commit - 1, height: 0)), "A short drag must return the page")
        check(!swipe.commits(CGSize(width: -120, height: 0)), "A backward drag must not complete the back")
        check(!swipe.commits(CGSize(width: 120, height: 200)), "A mostly vertical drag must not complete the back")
        check(swipe.offset(CGSize(width: 40, height: 0)) == 40, "A forward drag must follow the finger")
        check(swipe.offset(CGSize(width: -40, height: 0)) == 0, "A backward drag must not pull the page off its resting place")
        return (count, failures)
    }
}
