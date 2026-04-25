import SwiftUI

/// Color tokens. Liquid Glass surfaces use the `.glassEffect(...)` modifier directly at call sites —
/// see PopoverView / SettingsView. Tints flow through `Theme.accent`.
enum Theme {
    /// Brand accent — Teal Mint. Used for glass tints, heatmap, charts, action buttons.
    static let accent = Color(red: 0x00 / 255, green: 0xBF / 255, blue: 0xA5 / 255)

    /// Heatmap empty-cell base — adaptive grey, never accent-tinted.
    static let heatmapEmpty = Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.93, alpha: 1)
    })

    /// 5-step alpha multipliers for the heatmap (index 0 == empty, rendered with `heatmapEmpty`).
    static let heatmapAlphas: [Double] = [0.0, 0.15, 0.35, 0.6, 1.0]

    /// Below low-balance threshold colour.
    static let warning = Color.red
}
