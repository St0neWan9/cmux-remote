import CmuxRemoteCore

/// Owns local viewing position; scrolling never changes a producer or its input.
actor TerminalViewportState {
    private var manualTop: Int?
    private var automaticTop = 0
    private var maximumTop = 0
    func topRow(for snapshot: MirrorTerminalSnapshot, localRows: Int) -> Int? {
        maximumTop = max(0, snapshot.rows - localRows)
        let row = snapshot.renderGrid?["cursor"]["row"].int ?? 0
        automaticTop = min(maximumTop, max(0, row - max(0, localRows - 3)))
        if let manualTop { self.manualTop = min(maximumTop, manualTop) }
        return manualTop
    }
    func scroll(_ delta: Int) { manualTop = min(maximumTop, max(0, (manualTop ?? automaticTop) + delta)) }
    func followCursor() { manualTop = nil }
}
