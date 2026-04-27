import SwiftUI

/// Color tokens for a restrained macOS utility aesthetic. The brand palette is
/// low-saturation mineral blue with a small champagne accent; probe health
/// colors stay semantic and separate.
enum Theme {
    /// Primary brand accent — mineral blue, replacing the brighter teal.
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.40, green: 0.45, blue: 0.56, alpha: 1.0),
        dark: NSColor(srgbRed: 0.58, green: 0.64, blue: 0.76, alpha: 1.0)
    )

    static let accentMuted = adaptive(
        light: NSColor(srgbRed: 0.76, green: 0.79, blue: 0.86, alpha: 1.0),
        dark: NSColor(srgbRed: 0.30, green: 0.34, blue: 0.43, alpha: 1.0)
    )

    static let accentStrong = adaptive(
        light: NSColor(srgbRed: 0.25, green: 0.30, blue: 0.40, alpha: 1.0),
        dark: NSColor(srgbRed: 0.75, green: 0.79, blue: 0.88, alpha: 1.0)
    )

    /// Used sparingly for verified/selected states.
    static let champagne = adaptive(
        light: NSColor(srgbRed: 0.69, green: 0.61, blue: 0.41, alpha: 1.0),
        dark: NSColor(srgbRed: 0.78, green: 0.71, blue: 0.52, alpha: 1.0)
    )

    static let panelFill = adaptive(
        light: NSColor(srgbRed: 0.96, green: 0.965, blue: 0.975, alpha: 0.84),
        dark: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.82)
    )

    static let panelFillElevated = adaptive(
        light: NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 0.92),
        dark: NSColor(srgbRed: 0.17, green: 0.18, blue: 0.22, alpha: 0.88)
    )

    static let surfaceBorder = adaptive(
        light: NSColor(srgbRed: 0.70, green: 0.73, blue: 0.80, alpha: 0.42),
        dark: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.70, alpha: 0.30)
    )

    static let hairline = adaptive(
        light: NSColor(srgbRed: 0.78, green: 0.80, blue: 0.86, alpha: 0.42),
        dark: NSColor(srgbRed: 0.44, green: 0.47, blue: 0.55, alpha: 0.38)
    )

    static let metricSecondary = adaptive(
        light: NSColor(srgbRed: 0.37, green: 0.39, blue: 0.45, alpha: 1.0),
        dark: NSColor(srgbRed: 0.68, green: 0.70, blue: 0.76, alpha: 1.0)
    )

    /// Heatmap empty-cell base — adaptive grey, never accent-tinted.
    static let heatmapEmpty = Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.93, alpha: 1)
    })

    /// 5-step alpha multipliers for the heatmap (index 0 == empty, rendered with `heatmapEmpty`).
    static let heatmapAlphas: [Double] = [0.0, 0.15, 0.35, 0.6, 1.0]

    static let heatmapLevels: [Color] = [
        heatmapEmpty,
        adaptive(light: NSColor(srgbRed: 0.84, green: 0.87, blue: 0.92, alpha: 1.0),
                 dark: NSColor(srgbRed: 0.24, green: 0.27, blue: 0.34, alpha: 1.0)),
        adaptive(light: NSColor(srgbRed: 0.69, green: 0.74, blue: 0.83, alpha: 1.0),
                 dark: NSColor(srgbRed: 0.34, green: 0.39, blue: 0.50, alpha: 1.0)),
        adaptive(light: NSColor(srgbRed: 0.49, green: 0.56, blue: 0.70, alpha: 1.0),
                 dark: NSColor(srgbRed: 0.48, green: 0.55, blue: 0.69, alpha: 1.0)),
        adaptive(light: NSColor(srgbRed: 0.27, green: 0.34, blue: 0.48, alpha: 1.0),
                 dark: NSColor(srgbRed: 0.66, green: 0.72, blue: 0.84, alpha: 1.0)),
    ]

    /// Below low-balance threshold colour.
    static let warning = adaptive(
        light: NSColor(srgbRed: 0.68, green: 0.28, blue: 0.22, alpha: 1.0),
        dark: NSColor(srgbRed: 0.91, green: 0.45, blue: 0.36, alpha: 1.0)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}
