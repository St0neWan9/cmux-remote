import Foundation
import CmuxRemoteCore

/// Consumes local SGR pointer reports while retaining genuine keyboard bytes.
struct TerminalPointerInputDecoder {
    enum Event: Sendable { case keyboard(Data), paste(Data), scroll(Int) }
    private var pending: [UInt8] = []
    private var pasting = false
    private var pasteBytes = Data()
    var hasPending: Bool { !pasting && !pending.isEmpty }
    mutating func consume(_ chunk: Data) throws -> [Event] {
        pending.append(contentsOf: chunk)
        var events: [Event] = [], keyboard = Data()
        func flushKeyboard() { if !keyboard.isEmpty { events.append(.keyboard(keyboard)); keyboard.removeAll() } }
        while !pending.isEmpty {
            let delimiter: [UInt8] = pasting ? [27, 91, 50, 48, 49, 126] : [27, 91, 50, 48, 48, 126]
            if pending.starts(with: delimiter) {
                flushKeyboard(); pending.removeFirst(delimiter.count)
                if pasting, !pasteBytes.isEmpty { events.append(.paste(pasteBytes)) }
                pasteBytes.removeAll(); pasting.toggle(); continue
            }
            if pending.count < delimiter.count, delimiter.starts(with: pending) { break }
            if pasting {
                guard pasteBytes.count < 16_384 else { throw BridgeError("invalid_input", "Paste exceeded the input limit.") }
                pasteBytes.append(pending.removeFirst()); continue
            }
            if pending.first != 27 { keyboard.append(pending.removeFirst()); continue }
            if pending.count == 1 { break }
            if pending[1] != 91 { keyboard.append(pending.removeFirst()); continue }
            if pending.count == 2 { break }
            if pending[2] != 60 { keyboard.append(pending.removeFirst()); continue }
            guard let end = pending.dropFirst(3).firstIndex(where: { $0 == 77 || $0 == 109 }) else {
                guard pending.count <= 128 else { throw BridgeError("invalid_input", "Local pointer report exceeded its limit.") }
                break
            }
            flushKeyboard()
            let fields = String(decoding: pending[3..<end], as: UTF8.self).split(separator: ";")
            guard fields.count == 3, let button = Int(fields[0]), (0...255).contains(button),
                  fields.dropFirst().allSatisfy({ Int($0).map { (1...1_000_000).contains($0) } ?? false }) else {
                throw BridgeError("invalid_input", "Invalid local pointer report.")
            }
            if pending[end] == 77, button & 64 != 0, button & 3 < 2 {
                events.append(.scroll(button & 1 == 0 ? -3 : 3))
            }
            pending.removeFirst(end + 1)
        }
        flushKeyboard()
        return events
    }
    /// A lone Escape is a key; an incomplete pointer report must never be typed remotely.
    mutating func flushPending() -> [Event] {
        defer { pending.removeAll(); pasteBytes.removeAll(); pasting = false }
        guard !pending.isEmpty, !pasting, !pending.starts(with: [27, 91, 60]) else { return [] }
        return [.keyboard(Data(pending))]
    }
}
