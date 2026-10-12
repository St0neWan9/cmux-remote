import SwiftUI

/// Visible pages restore native gestures after navigation and layout updates.
struct InteractivePopInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InteractivePopController { InteractivePopController() }
    func updateUIViewController(_ controller: InteractivePopController, context: Context) { controller.installDelegate() }
    static func dismantleUIViewController(_ controller: InteractivePopController, coordinator: ()) {
        controller.restoreDelegate()
    }
}
