import XCTest
import SwiftUI
@testable import CmuxRemote

/// Hosted UIKit/SwiftUI checks exercise the actual navigation and surface components.
@MainActor
final class MobileNavigationTests: XCTestCase {
    func testHiddenHeaderKeepsNativePopAndRejectsRootPop() async throws {
        let route = NavigationTestRoute()
        let host = UIHostingController(rootView: NavigationTestRoot(route: route))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.navigation(in: host)?.interactivePopGestureRecognizer?.delegate is InteractivePopController
        }, object: nil)
        await fulfillment(of: [installed], timeout: 5)
        let navigation = try XCTUnwrap(navigation(in: host))
        let gesture = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        let owner = try XCTUnwrap(gesture.delegate as? InteractivePopController)
        XCTAssertTrue(gesture.isEnabled)
        XCTAssertFalse(owner.gestureRecognizerShouldBegin(gesture))
        for _ in 0..<3 {
            route.pushed = true
            let pushed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                navigation.viewControllers.count == 2 && navigation.transitionCoordinator == nil
            }, object: nil)
            await fulfillment(of: [pushed], timeout: 5)
            let detailOwner = try XCTUnwrap(gesture.delegate as? InteractivePopController)
            XCTAssertTrue(gesture.isEnabled)
            XCTAssertTrue(detailOwner.gestureRecognizerShouldBegin(gesture))
            if #available(iOS 26.0, *), let contentGesture = navigation.interactiveContentPopGestureRecognizer {
                XCTAssertTrue(contentGesture.isEnabled)
                XCTAssertTrue(contentGesture.delegate is InteractivePopController)
                XCTAssertTrue(detailOwner.gestureRecognizerShouldBegin(contentGesture))
            }
            route.pushed = false
            let popped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil
            }, object: nil)
            await fulfillment(of: [popped], timeout: 5)
            let rootOwner = try XCTUnwrap(gesture.delegate as? InteractivePopController)
            XCTAssertFalse(rootOwner.gestureRecognizerShouldBegin(gesture))
        }
        let lastOwner = try XCTUnwrap(gesture.delegate as? InteractivePopController)
        lastOwner.restoreDelegate()
        XCTAssertFalse(gesture.delegate === lastOwner)
    }

    func testShortAndLongCardsFillTheSameInsetColumn() async {
        for width in [320.0, 430.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let measured = expectation(description: "Both cards laid out")
                measured.expectedFulfillmentCount = 2
                let host = UIHostingController(rootView:
                    VStack(spacing: MobileDesign.sectionGap) {
                        card("Short", measured: measured, available: width - 40)
                        card(String(repeating: "Long identity value ", count: 20), measured: measured, available: width - 40)
                    }.padding(MobileDesign.pageInset).environment(\.dynamicTypeSize, size)
                )
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1200))
                window.rootViewController = host; window.makeKeyAndVisible()
                await fulfillment(of: [measured], timeout: 5)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }

    private func card(_ text: String, measured: XCTestExpectation, available: CGFloat) -> some View {
        Text(text).modifier(FloatingSurface()).background {
            GeometryReader { geometry in
                Color.clear.onAppear {
                    XCTAssertEqual(geometry.size.width, available, accuracy: 0.5)
                    measured.fulfill()
                }
            }
        }
    }
    private func navigation(in controller: UIViewController) -> UINavigationController? {
        if let value = controller as? UINavigationController { return value }
        return controller.children.compactMap { navigation(in: $0) }.first
    }
}
