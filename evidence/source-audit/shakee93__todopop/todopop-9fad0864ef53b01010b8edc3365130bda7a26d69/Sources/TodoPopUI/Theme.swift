import SwiftUI

/// Central design tokens so spacing, color, and motion stay consistent across the app.
enum Theme {
    // Layout
    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 460
    static let hPadding: CGFloat = 14
    static let rowCorner: CGFloat = 8
    static let rowVPadding: CGFloat = 7

    // Color — accent follows the user's system accent (native, respectful default).
    static let accent = Color.accentColor

    /// Subtle surface fills layered over the window vibrancy.
    static func fill(_ level: Double) -> Color { Color.primary.opacity(level) }
    static let hoverFill = Color.primary.opacity(0.07)
    static let fieldFill = Color.primary.opacity(0.05)
    static let fieldFillActive = Color.primary.opacity(0.09)
    static let trackFill = Color.primary.opacity(0.10)

    static let completedRowOpacity: Double = 0.68

    // Motion
    static let nav = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let pop = Animation.spring(response: 0.30, dampingFraction: 0.62)
    static let ease = Animation.easeOut(duration: 0.13)

    static var progressGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.75), accent],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
