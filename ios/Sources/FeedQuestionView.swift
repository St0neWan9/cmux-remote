import SwiftUI
import CmuxRemoteCore

/// Collects one label-based answer per question, matching cmux's Feed contract.
struct FeedQuestionView: View {
    let questions: [JSONValue]
    let busy: Bool
    let submit: ([String]) -> Void
    @State private var selected: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]
    private var answers: [String] {
        questions.indices.compactMap { index in
            let text = (custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
            let labels = (questions[index]["options"].array ?? []).compactMap { $0["label"].string }.filter { selected[index]?.contains($0) == true }
            return labels.isEmpty ? nil : labels.joined(separator: ", ")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                Text(question["prompt"].string ?? question["question"].string ?? "")
                ForEach(Array((question["options"].array ?? []).enumerated()), id: \.offset) { _, option in
                    let label = option["label"].string ?? ""
                    Button {
                        var values = selected[index] ?? []
                        if question["multi_select"].bool == true {
                            if values.contains(label) { values.remove(label) } else { values.insert(label) }
                        } else { values = [label] }
                        selected[index] = values
                    } label: {
                        Label(label, systemImage: selected[index]?.contains(label) == true ? "checkmark.circle.fill" : "circle")
                    }.buttonStyle(.borderless).disabled(busy)
                }
                TextField(String(localized: "feed.custom"), text: Binding(get: { custom[index] ?? "" }, set: { custom[index] = $0 }))
                    .padding(12).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
            }
            Button(String(localized: "feed.submit")) { submit(answers) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(busy || answers.count != questions.count)
        }
    }
}
