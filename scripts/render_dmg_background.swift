import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render_dmg_background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 560, height: 340)
let image = NSImage(size: size)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.978, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let panelRect = NSRect(x: 28, y: 34, width: 504, height: 272)
NSColor.white.withAlphaComponent(0.78).setFill()
roundedRect(panelRect, radius: 22).fill()
NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.88, alpha: 0.7).setStroke()
roundedRect(panelRect, radius: 22).lineWidth = 1
roundedRect(panelRect, radius: 22).stroke()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.18, alpha: 1)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.34, green: 0.41, blue: 0.47, alpha: 1)
]

"Install APIStatusBar".draw(at: NSPoint(x: 42, y: 276), withAttributes: titleAttributes)
"Drag the app into Applications, then launch it from there.".draw(at: NSPoint(x: 42, y: 254),
                                                                 withAttributes: subtitleAttributes)

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 224, y: 172))
arrowPath.curve(to: NSPoint(x: 336, y: 172),
                controlPoint1: NSPoint(x: 260, y: 190),
                controlPoint2: NSPoint(x: 300, y: 190))
arrowPath.lineWidth = 5
arrowPath.lineCapStyle = .round
NSColor(calibratedRed: 0.02, green: 0.73, blue: 0.46, alpha: 0.92).setStroke()
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 336, y: 172))
arrowHead.line(to: NSPoint(x: 318, y: 186))
arrowHead.move(to: NSPoint(x: 336, y: 172))
arrowHead.line(to: NSPoint(x: 318, y: 158))
arrowHead.lineWidth = 5
arrowHead.lineCapStyle = .round
arrowHead.stroke()

let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.31, alpha: 0.82)
]
"Drag to install".draw(at: NSPoint(x: 237, y: 135), withAttributes: hintAttributes)

NSColor(calibratedRed: 0.02, green: 0.73, blue: 0.46, alpha: 0.12).setFill()
roundedRect(NSRect(x: 82, y: 82, width: 118, height: 118), radius: 26).fill()
roundedRect(NSRect(x: 360, y: 82, width: 118, height: 118), radius: 26).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to render background\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
