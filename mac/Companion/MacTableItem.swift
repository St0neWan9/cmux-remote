import Foundation

/// A stable table row; `id` is the exact owner-side identifier the row's actions use.
struct MacTableItem: Identifiable, Hashable {
    let id: String
    let title: String
    var detail = ""
    var symbol: String?
}
