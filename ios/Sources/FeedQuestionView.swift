import SwiftUI
import CmuxRemoteCore

/// Collects one label-based answer per question, in the order supplied by cmux.
struct FeedQuestionView: View {
    let questions: [JSONValue]
    let busy: Bool
    let submit: ([String]) -> Void
    @State private var drafts: [Int: FeedQuestionDraft] = [:]
    private var answers: [String] {
        return questions.indices.compactMap { index in
            (drafts[index] ?? FeedQuestionDraft()).answer(options: (questions[index]["options"].array ?? []).enumerated().map { FeedQuestionOption(json: $0.element, fallbackIndex: $0.offset) })
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 12) {
                    if let header = question["header"].string { Text(header).font(.caption).foregroundStyle(.secondary) }
                    Text(question["prompt"].string ?? question["question"].string ?? "").font(.body.weight(.medium))
                    let options = (question["options"].array ?? []).enumerated().map { FeedQuestionOption(json: $0.element, fallbackIndex: $0.offset) }
                    ForEach(options) { option in
                        let label = option.label
                        Button {
                            var draft = drafts[index] ?? FeedQuestionDraft(); draft.choose(option.id, multi: question["multi_select"].bool == true); drafts[index] = draft
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: drafts[index]?.selected.contains(option.id) == true ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(label)
                                    if let description = option.detail { Text(description).font(.footnote).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("feed.question.option." + String(index) + "." + option.id)
                            .accessibilityAddTraits(drafts[index]?.selected.contains(option.id) == true ? .isSelected : [])
                    }
                    TextField(String(localized: "feed.custom"), text: Binding(get: { drafts[index]?.customText ?? "" }, set: { text in
                        var draft = drafts[index] ?? FeedQuestionDraft(); draft.typeCustom(text); drafts[index] = draft
                    }), axis: .vertical).lineLimit(1...4)
                        .modifier(FloatingInput())
                        .disabled(busy).accessibilityIdentifier("feed.question.custom." + String(index))
                }
            }
            ActionRow {
            Button(String(localized: "feed.submit")) { submit(answers) }
                .buttonStyle(FloatingButtonStyle(prominent: true))
                .disabled(busy || (answers.isEmpty && !(!questions.isEmpty && questions.allSatisfy { ($0["options"].array ?? []).isEmpty })))
                .accessibilityIdentifier("feed.question.submit")
            Button(String(localized: "feed.skip_questions")) { submit([]) }.buttonStyle(FloatingButtonStyle()).disabled(busy || questions.isEmpty)
                .accessibilityIdentifier("feed.question.skip")
            }
        }
    }
}
