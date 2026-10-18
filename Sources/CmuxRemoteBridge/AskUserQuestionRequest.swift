import Foundation
import CmuxRemoteCore

/// The AskUserQuestion a Claude Agent is blocked on in a daemon terminal, read from its own transcript.
///
/// The terminal shows only the first question of a request, so the questions, their options and whether each
/// takes several answers come from the tool call the Agent recorded. The prompts are the exact text the
/// conversation card shows, which is what lets the card answer its own question.
///
/// Answering drives Claude Code's menu with keys, never typed text: a single-choice question takes its option's
/// number and moves on, a multi-choice question takes the number of every chosen option and then Right, and a
/// request with more than one question, or a multi-choice one, ends on a review page that 1 submits. A request
/// of one single-choice question is submitted by its number alone.
struct AskUserQuestionRequest: Sendable, Equatable {
    struct Option: Sendable, Equatable { let label: String; let detail: String? }
    struct Question: Sendable, Equatable { let prompt: String; let header: String?; let options: [Option]; let multiSelect: Bool }
    let toolUseID: String
    let questions: [Question]

    /// The newest AskUserQuestion in `transcript` that has no result yet.
    static func pending(in transcript: Data) -> AskUserQuestionRequest? {
        var latest: AskUserQuestionRequest?
        for line in transcript.split(separator: UInt8(ascii: "\n")) {
            guard let row = try? JSONDecoder().decode(JSONValue.self, from: Data(line)) else { continue }
            for block in row["message"]["content"].array ?? [] {
                if block["type"].string == "tool_use", block["name"].string == "AskUserQuestion", let id = block["id"].string,
                   let request = parse(id: id, input: block["input"]) { latest = request }
                if block["type"].string == "tool_result", block["tool_use_id"].string == latest?.toolUseID { latest = nil }
            }
        }
        return latest
    }
    private static func parse(id: String, input: JSONValue) -> AskUserQuestionRequest? {
        let raw = input["questions"].array ?? []
        let questions: [Question] = raw.compactMap { item in
            guard let prompt = item["question"].string, !prompt.isEmpty else { return nil }
            let options = (item["options"].array ?? []).compactMap { option in option["label"].string.map { Option(label: $0, detail: option["description"].string) } }
            return Question(prompt: prompt, header: item["header"].string, options: options, multiSelect: item["multiSelect"].bool == true)
        }
        // Only a request the menu can show in full is offered: every question parsed, each option reachable by one digit.
        guard !questions.isEmpty, questions.count == raw.count, questions.count <= 4,
              questions.allSatisfy({ (1...8).contains($0.options.count) }) else { return nil }
        return AskUserQuestionRequest(toolUseID: id, questions: questions)
    }

    /// Whether `lines` is Claude Code's menu for this request, untouched: on its first question, nothing answered yet.
    ///
    /// The keys are computed from that starting point, so a menu someone already moved through on the Mac is not offered.
    func isFreshMenu(_ lines: [String]) -> Bool {
        let tail = lines.suffix(4).joined(separator: " ").lowercased()
        guard tail.contains("enter to select"), tail.contains("esc to cancel") else { return false }
        guard lines.contains(questions[0].prompt), !lines.contains(where: { $0.contains("☒") || $0.hasPrefix("Review your answers") }) else { return false }
        let first = questions[0].options[0].label
        let cursor = questions[0].multiSelect ? "❯ 1. [ ] " + first : "❯ 1. " + first
        return lines.contains(cursor) || lines.contains(cursor.replacingOccurrences(of: "❯ ", with: "❯\u{00a0}"))
    }

    /// The questions as the phone's question form reads them; option IDs are the digits that choose them.
    var formQuestions: [JSONValue] {
        questions.enumerated().map { index, question in
            var fields: [String: JSONValue] = ["id": .string("q\(index)"), "prompt": .string(question.prompt), "multi_select": .bool(question.multiSelect),
                                               // The menu's "Type something" and its cancel are not driven from the phone.
                                               "allow_custom": .bool(false), "allow_skip": .bool(false),
                                               "options": .array(question.options.enumerated().map { number, option in
                                                   var item: [String: JSONValue] = ["id": .string(String(number + 1)), "label": .string(option.label)]
                                                   if let detail = option.detail { item["description"] = .string(detail) }
                                                   return .object(item)
                                               })]
            if let header = question.header { fields["header"] = .string(header) }
            return .object(fields)
        }
    }

    /// The keys that give these answers, one per question in order; nil when an answer is not one the menu offers.
    ///
    /// The phone joins the labels of a multi-choice answer with ", ". A label may itself contain that separator,
    /// so the answer is matched against every combination of the question's options in their order, never split.
    func keys(for selections: [String]) -> [String]? {
        guard selections.count == questions.count else { return nil }
        var keys: [String] = []
        for (question, answer) in zip(questions, selections) {
            let labels = question.options.map(\.label)
            if question.multiSelect {
                let combinations = (1..<(1 << labels.count)).map { mask in labels.indices.filter { mask & (1 << $0) != 0 } }
                let matches = combinations.filter { $0.map { labels[$0] }.joined(separator: ", ") == answer }
                guard matches.count == 1, let chosen = matches.first else { return nil }
                keys += chosen.map { String($0 + 1) } + ["right"]
            } else {
                guard let index = labels.firstIndex(of: answer), labels.lastIndex(of: answer) == index else { return nil }
                keys.append(String(index + 1))
            }
        }
        // One single-choice question submits with its number; anything else stops on the review page.
        if !(questions.count == 1 && !questions[0].multiSelect) { keys.append("1") }
        return keys
    }
}
