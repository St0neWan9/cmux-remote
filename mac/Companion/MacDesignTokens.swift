import Foundation

/// The Amphetamine-style preference pane values specified in docs/DESIGN-SYSTEM.md.
struct MacDesignTokens {
    let windowWidth: CGFloat = 640
    let controlWidth: CGFloat = 420
    let verticalInset: CGFloat = 28
    let labelSpacing: CGFloat = 8
    let groupSpacing: CGFloat = 24
    let rowSpacing: CGFloat = 8
    let noteIndent: CGFloat = 20
    let tableHeight: CGFloat = 132
    let qrCodeSize: CGFloat = 200
    let qrQuietZone: CGFloat = 16
    /// The Bridge log is its own resizable window, not a preference page.
    let logWindowWidth: CGFloat = 760
    let logWindowHeight: CGFloat = 520
    let logMinimumWidth: CGFloat = 560
    let logMinimumHeight: CGFloat = 360
    let logInset: CGFloat = 16
    let logSearchWidth: CGFloat = 220
}
