import XCTest
@testable import CmuxRemote

final class DrawerDragTests: XCTestCase {
    func testOpeningCommitsFromFingerPositionToOpenTarget() {
        var drag = DrawerDragState()
        drag.update(translation: 170, width: 300, opening: true)
        XCTAssertEqual(drag.resolvedOffset(isPresented: false, width: 300), 170)
        let open = drag.finish(predictedTranslation: 210, width: 300, opening: true, current: false, horizontal: true)
        XCTAssertTrue(open)
        XCTAssertEqual(drag.resolvedOffset(isPresented: open, width: 300), 300)
    }
    func testClosingAndCancelledDirectionSettleWithoutResidualDisplacement() {
        var drag = DrawerDragState()
        drag.update(translation: -120, width: 300, opening: false)
        XCTAssertEqual(drag.resolvedOffset(isPresented: true, width: 300), 180)
        let closed = drag.finish(predictedTranslation: -150, width: 300, opening: false, current: true, horizontal: true)
        XCTAssertFalse(closed)
        XCTAssertEqual(drag.resolvedOffset(isPresented: closed, width: 300), 0)
        drag.update(translation: 40, width: 300, opening: true)
        let cancelled = drag.finish(predictedTranslation: 290, width: 300, opening: true, current: false, horizontal: false)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(drag.resolvedOffset(isPresented: cancelled, width: 300), 0)
    }
    func testShortDragReturnsToClosedAndClampsOvershoot() {
        var drag = DrawerDragState()
        drag.update(translation: 900, width: 300, opening: true)
        XCTAssertEqual(drag.resolvedOffset(isPresented: false, width: 300), 300)
        drag.update(translation: -900, width: 300, opening: false)
        XCTAssertEqual(drag.resolvedOffset(isPresented: true, width: 300), 0)
        drag.cancel()
        XCTAssertEqual(drag.resolvedOffset(isPresented: true, width: 300), 300)
        drag.update(translation: 30, width: 300, opening: true)
        let target = drag.finish(predictedTranslation: 40, width: 300, opening: true, current: false, horizontal: true)
        XCTAssertFalse(target)
        XCTAssertEqual(drag.resolvedOffset(isPresented: target, width: 300), 0)
    }
}
