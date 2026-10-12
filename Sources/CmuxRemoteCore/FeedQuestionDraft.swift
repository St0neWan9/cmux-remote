import Foundation

/// One question's explicit answer mode prevents stale custom text from overriding a later option.
public struct FeedQuestionDraft: Sendable, Equatable {
    public private(set) var selected: Set<String> = []
    public private(set) var customText = ""
    public private(set) var usesCustom = false
    public init() {}
    public mutating func choose(_ optionID: String, multi: Bool) {
        usesCustom = false
        if multi { if selected.contains(optionID) { selected.remove(optionID) } else { selected.insert(optionID) } }
        else { selected = [optionID] }
    }
    public mutating func typeCustom(_ text: String) { customText = text; usesCustom = true; selected = [] }
    public func answer(options: [FeedQuestionOption]) -> String? {
        if usesCustom { let value = customText.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
        let labels = options.filter { selected.contains($0.id) }.map(\.label); return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }
}
