import SwiftUI
@testable import TermRemote

struct NavigationTestRoot: View {
    @Bindable var route: NavigationTestRoute
    var body: some View {
        AppNavigationStack {
            WhitePage(title: "Navigation fixture", dismissal: .none) { Text("Root") }
                .navigationDestination(isPresented: $route.pushed) {
                    WhitePage(title: "Detail") { Text("Detail body") }
                }
        }
    }
}
