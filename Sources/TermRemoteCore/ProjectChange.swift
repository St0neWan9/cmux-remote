import Foundation

/// One porcelain-v1 NUL-delimited Git change, preserving spaces and rename source paths.
public struct ProjectChange: Identifiable, Sendable, Equatable {
    public let status: String
    public let path: String
    public let previousPath: String?
    public var id: String { status + ":" + path }
    public init(status: String, path: String, previousPath: String? = nil) { self.status = status; self.path = path; self.previousPath = previousPath }
    public static func parse(entries: [JSONValue]) -> [Self] {
        var result: [Self] = []; var index = 0
        while index < entries.count {
            let row = entries[index].string ?? ""; index += 1
            guard row.count >= 4 else { continue }
            let status = String(row.prefix(2))
            guard row.dropFirst(2).first == " ", status.allSatisfy({ " MADRCU?!".contains($0) }) else { continue }
            let path = String(row.dropFirst(3)); guard !path.isEmpty else { continue }
            var previous: String?
            if status.contains("R") || status.contains("C"), index < entries.count { previous = entries[index].string; index += 1 }
            result.append(Self(status: status, path: path, previousPath: previous))
        }
        return result
    }
}
