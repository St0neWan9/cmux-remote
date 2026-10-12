import SwiftUI
import CmuxRemoteCore

/// Each decision is an explicit user action; extended permission/plan modes explain their effect first.
struct FeedDecisionControls: View {
    let item: JSONValue
    let busy: Bool
    let submit: (FeedDecisionMode, String?) -> Void
    @State private var feedback = ""
    @State private var confirming: FeedDecisionMode?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item["kind"].string == "exitPlan" {
                TextField(String(localized: "feed.feedback"), text: $feedback, axis: .vertical).lineLimit(1...4)
                    .padding(12).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.1), lineWidth: 0.5)).disabled(busy)
            }
            let modes = FeedDecisionPolicy().modes(for: item)
            HStack {
                if let primary = modes.first(where: { $0 == .once || $0 == .manual }) {
                    Button(primary.localizedTitle) { submit(primary, feedback) }
                }
                if modes.contains(.deny) { Button(String(localized: "feed.deny"), role: .destructive) { submit(.deny, feedback) } }
                if modes.contains(where: \.needsExplanation) {
                    Menu {
                        ForEach(modes.filter(\.needsExplanation), id: \.rawValue) { mode in
                            Button(mode.localizedTitle) { confirming = mode }
                        }
                    } label: { Label(String(localized: "feed.more_modes"), systemImage: "ellipsis") }
                }
            }.buttonStyle(FloatingButtonStyle()).disabled(busy)
        }.alert(String(localized: "feed.confirm_mode"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button(String(localized: "feed.confirm")) { if let mode = confirming { submit(mode, feedback) }; confirming = nil }
            Button(String(localized: "pair.cancel"), role: .cancel) { confirming = nil }
        } message: {
            if let mode = confirming { Text(mode.explanation) }
        }
    }
}
