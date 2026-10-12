import Foundation
import CmuxRemoteCore

/// Selects a cold restore or positioned repaint for one viewer's screen lifetime.
struct TerminalPresentationSequence: Sendable {
    private var key: String?
    mutating func next(_ snapshot: MirrorTerminalSnapshot) -> Data {
        let repaint = snapshot.presentationKey != nil && snapshot.presentationKey == key
        key = snapshot.presentationKey
        return repaint ? (snapshot.repaintBytes ?? snapshot.bytes) : snapshot.bytes
    }
}
