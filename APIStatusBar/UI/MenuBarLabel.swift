import SwiftUI

struct MenuBarLabel: View {
    let snapshot: QuotaSnapshot?
    let formatter: QuotaFormatter
    let lowBalanceThresholdRMB: Double
    let hasError: Bool
    let isConfigured: Bool

    var body: some View {
        iconView
            .frame(width: 16, height: 16)
        .font(.system(size: 13, weight: .medium))
    }

    @ViewBuilder
    private var iconView: some View {
        if !isConfigured {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        } else if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
        } else {
            AppLogoMark()
                .foregroundStyle(isLow ? Theme.warning : .primary)
        }
    }

    private var rmb: Double? {
        guard let snapshot else { return nil }
        return formatter.rmb(fromRaw: snapshot.quotaRaw)
    }

    private var isLow: Bool {
        guard let rmb else { return false }
        return rmb < lowBalanceThresholdRMB
    }
}

struct AppLogoMark: View {
    var body: some View {
        AngularLogoShape()
            .stroke(style: StrokeStyle(lineWidth: 1.45,
                                       lineCap: .butt,
                                       lineJoin: .miter))
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 16, height: 16)
            .accessibilityLabel("APIStatusBar")
    }
}

struct AngularLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let center = CGPoint(x: origin.x + side / 2, y: origin.y + side / 2)
        let shapeScale = side / 18 * 1.22
        let base = [
            CGPoint(x: 1.35, y: -0.7),
            CGPoint(x: 4.15, y: -2.35),
            CGPoint(x: 5.95, y: -1.25),
            CGPoint(x: 5.95, y: 2.1),
            CGPoint(x: 4.45, y: 2.95),
            CGPoint(x: 4.45, y: 0.25),
            CGPoint(x: 2.25, y: -1.0)
        ]
        var path = Path()
        for index in 0..<6 {
            let angle = Double(index) * Double.pi / 3
            let cosine = CGFloat(cos(angle))
            let sine = CGFloat(sin(angle))
            let points = base.map { point in
                let x = point.x * shapeScale
                let y = point.y * shapeScale
                return CGPoint(x: center.x + x * cosine - y * sine,
                               y: center.y + x * sine + y * cosine)
            }
            guard let first = points.first else { continue }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }
}
