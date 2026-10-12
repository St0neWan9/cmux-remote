import CoreGraphics

/// Keeps interactive displacement until the presentation binding settles in the same transaction.
struct DrawerDragState {
    private(set) var offset: CGFloat?
    mutating func update(translation: CGFloat, width: CGFloat, opening: Bool) {
        offset = max(0, min(width, (opening ? 0 : width) + translation))
    }
    func resolvedOffset(isPresented: Bool, width: CGFloat) -> CGFloat {
        offset ?? (isPresented ? width : 0)
    }
    mutating func finish(predictedTranslation: CGFloat, width: CGFloat, opening: Bool, current: Bool, horizontal: Bool) -> Bool {
        let target = horizontal ? (opening ? predictedTranslation > width * 0.25 : predictedTranslation >= -width * 0.25) : current
        offset = nil
        return target
    }
    mutating func cancel() { offset = nil }
}
