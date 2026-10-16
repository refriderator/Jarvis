// Draws Jarvis's app icon: a greyscale macOS squircle with just the notch hanging from its top edge.
// Usage: swift scripts/make-icon.swift <out.png>   (1024 x 1024; scripts/make-icon.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let grey = { (white: CGFloat, alpha: CGFloat) in CGColor(gray: white, alpha: alpha) }

// The body on Apple's icon grid: 824 pt inside the 1024 canvas, continuous corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).cgPath

// Soft drop shadow under the body, like the system's icons.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: grey(0, 0.45))
ctx.addPath(squircle)
ctx.setFillColor(grey(0.16, 1))
ctx.fillPath()
ctx.restoreGState()

// Everything else stays inside the body.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Near-black like the system's tinted icons (Messages'), a touch lighter at the top (y goes up in Core Graphics).
let fill = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                      colors: [grey(0.13, 1), grey(0.05, 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

// A thin line across the middle of the icon like a menu bar, and the notch hanging from it: wide, its shoulders curving into
// the line, rounded bottom corners. One shape, so they read as one piece.
let lineHeight: CGFloat = 14
let notchWidth: CGFloat = 520, notchHeight: CGFloat = 150, shoulder: CGFloat = 34, corner: CGFloat = 64
// The line and notch together are centred top to bottom.
let lineY = body.midY + (notchHeight - lineHeight) / 2
let top = lineY, left = body.midX - notchWidth / 2, right = body.midX + notchWidth / 2
let notch = CGMutablePath()
notch.move(to: CGPoint(x: body.minX, y: top + lineHeight))
notch.addLine(to: CGPoint(x: body.maxX, y: top + lineHeight))
notch.addLine(to: CGPoint(x: body.maxX, y: top))
notch.addLine(to: CGPoint(x: right + shoulder, y: top))
notch.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top - shoulder), radius: shoulder)
notch.addArc(tangent1End: CGPoint(x: right, y: top - notchHeight), tangent2End: CGPoint(x: body.midX, y: top - notchHeight), radius: corner)
notch.addArc(tangent1End: CGPoint(x: left, y: top - notchHeight), tangent2End: CGPoint(x: left, y: top), radius: corner)
notch.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left - shoulder, y: top), radius: shoulder)
notch.addLine(to: CGPoint(x: body.minX, y: top))
notch.closeSubpath()

// A soft light around it, the glow the open notch has.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: grey(1, 0.22))
ctx.addPath(notch)
ctx.setFillColor(grey(0.7, 1))
ctx.fillPath()
ctx.restoreGState()
// The soft silver of the system's tinted icons (like Messages' bubble): lighter along the line, a little
// darker toward the notch's rounded bottom.
let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                       colors: [grey(0.86, 1), grey(0.66, 1)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addPath(notch)
ctx.clip()
ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: top + lineHeight), end: CGPoint(x: 0, y: top - notchHeight), options: [])
ctx.restoreGState()

// A hairline of light along the top edge of the glass, broken by the notch.
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(squircle)
ctx.setStrokeColor(grey(1, 0.14))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: out))
print("Wrote \(out)")
