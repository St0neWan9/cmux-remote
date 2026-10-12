import SwiftUI

/// Clips foreground ink to the same full-screen rounded boundary as its floating background.
struct DrawerPanelShape: Shape {
    let topInset: CGFloat
    let bottomInset: CGFloat
    var cornerRadius: CGFloat
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(x: rect.minX, y: rect.minY - topInset,
            width: rect.width, height: rect.height + topInset + bottomInset), cornerRadius: cornerRadius)
    }
}
