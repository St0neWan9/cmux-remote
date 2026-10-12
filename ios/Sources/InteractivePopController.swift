import UIKit

/// Hidden SwiftUI bars otherwise disable UIKit's native interactive pop recognizer.
final class InteractivePopController: UIViewController, UIGestureRecognizerDelegate {
    private weak var installedNavigation: UINavigationController?
    private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
    private weak var previousContentDelegate: (any UIGestureRecognizerDelegate)?

    override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installDelegate()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installDelegate()
    }
    func installDelegate() {
        guard viewIfLoaded?.window != nil else { return }
        guard let navigation = navigationController,
              let gesture = navigation.interactivePopGestureRecognizer else { return }
        if installedNavigation !== navigation {
            restoreDelegate()
            installedNavigation = navigation
            previousDelegate = gesture.delegate
            if #available(iOS 26.0, *) { previousContentDelegate = navigation.interactiveContentPopGestureRecognizer?.delegate }
        }
        gesture.delegate = self
        gesture.isEnabled = true
        if #available(iOS 26.0, *), let contentGesture = navigation.interactiveContentPopGestureRecognizer {
            contentGesture.delegate = self
            contentGesture.isEnabled = true
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation = installedNavigation else { return false }
        guard navigation.viewControllers.count > 1, navigation.transitionCoordinator == nil else { return false }
        if #available(iOS 26.0, *), gestureRecognizer === navigation.interactiveContentPopGestureRecognizer,
           let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: navigation.view)
            let forward = navigation.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -velocity.x : velocity.x
            if velocity != .zero { return forward > 0 && abs(velocity.x) > abs(velocity.y) }
        }
        return true
    }

    func restoreDelegate() {
        if let gesture = installedNavigation?.interactivePopGestureRecognizer, gesture.delegate === self {
            gesture.delegate = previousDelegate
        }
        if #available(iOS 26.0, *), let gesture = installedNavigation?.interactiveContentPopGestureRecognizer, gesture.delegate === self {
            gesture.delegate = previousContentDelegate
        }
        installedNavigation = nil
        previousDelegate = nil
        previousContentDelegate = nil
    }
}
