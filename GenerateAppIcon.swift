#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Well Control App Icon Generator
// Creates a modern, professional icon with a wellbore/pressure gauge theme

func createAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let center = CGPoint(x: s/2, y: s/2)
    let cornerRadius = s * 0.22

    // Background - dark gradient
    let backgroundPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: cornerRadius, yRadius: cornerRadius)

    // Create gradient background
    let darkColor = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
    let lighterColor = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.28, alpha: 1.0)

    let gradient = NSGradient(starting: lighterColor, ending: darkColor)
    gradient?.draw(in: backgroundPath, angle: -45)

    // Draw wellbore representation (vertical pipe)
    let pipeWidth = s * 0.12
    let pipeX = center.x - pipeWidth / 2
    let pipeTop = s * 0.15
    let pipeBottom = s * 0.75

    // Outer casing (gray)
    let casingColor = NSColor(calibratedRed: 0.45, green: 0.5, blue: 0.55, alpha: 1.0)
    casingColor.setFill()
    let casingPath = NSBezierPath(roundedRect: NSRect(x: pipeX - s*0.03, y: pipeTop, width: pipeWidth + s*0.06, height: pipeBottom - pipeTop), xRadius: s*0.02, yRadius: s*0.02)
    casingPath.fill()

    // Inner wellbore (darker)
    let wellboreColor = NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.25, alpha: 1.0)
    wellboreColor.setFill()
    let wellborePath = NSBezierPath(roundedRect: NSRect(x: pipeX, y: pipeTop + s*0.02, width: pipeWidth, height: pipeBottom - pipeTop - s*0.04), xRadius: s*0.01, yRadius: s*0.01)
    wellborePath.fill()

    // Fluid levels in wellbore - cement (orange) at bottom
    let cementColor = NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.2, alpha: 1.0)
    cementColor.setFill()
    let cementHeight = s * 0.25
    let cementPath = NSBezierPath(rect: NSRect(x: pipeX + s*0.01, y: pipeTop + s*0.03, width: pipeWidth - s*0.02, height: cementHeight))
    cementPath.fill()

    // Mud (brown) above cement
    let mudColor = NSColor(calibratedRed: 0.55, green: 0.4, blue: 0.25, alpha: 1.0)
    mudColor.setFill()
    let mudPath = NSBezierPath(rect: NSRect(x: pipeX + s*0.01, y: pipeTop + s*0.03 + cementHeight, width: pipeWidth - s*0.02, height: s * 0.2))
    mudPath.fill()

    // Draw pressure gauge on the right
    let gaugeRadius = s * 0.18
    let gaugeCenter = CGPoint(x: s * 0.72, y: s * 0.65)

    // Gauge background
    let gaugeBackColor = NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.2, alpha: 1.0)
    gaugeBackColor.setFill()
    let gaugePath = NSBezierPath(ovalIn: NSRect(x: gaugeCenter.x - gaugeRadius, y: gaugeCenter.y - gaugeRadius, width: gaugeRadius * 2, height: gaugeRadius * 2))
    gaugePath.fill()

    // Gauge rim
    let gaugeRimColor = NSColor(calibratedRed: 0.5, green: 0.55, blue: 0.6, alpha: 1.0)
    gaugeRimColor.setStroke()
    gaugePath.lineWidth = s * 0.015
    gaugePath.stroke()

    // Gauge needle (pointing to ~70%)
    let needleColor = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.4, alpha: 1.0) // Green for safe
    needleColor.setStroke()
    let needlePath = NSBezierPath()
    let needleAngle: CGFloat = .pi * 0.3 // About 70% of range
    let needleLength = gaugeRadius * 0.7
    needlePath.move(to: gaugeCenter)
    needlePath.line(to: CGPoint(
        x: gaugeCenter.x + cos(needleAngle + .pi) * needleLength,
        y: gaugeCenter.y + sin(needleAngle + .pi) * needleLength
    ))
    needlePath.lineWidth = s * 0.02
    needlePath.lineCapStyle = .round
    needlePath.stroke()

    // Center dot of gauge
    NSColor.white.setFill()
    let centerDotPath = NSBezierPath(ovalIn: NSRect(x: gaugeCenter.x - s*0.02, y: gaugeCenter.y - s*0.02, width: s*0.04, height: s*0.04))
    centerDotPath.fill()

    // Draw "W" letter stylized at top left
    let letterColor = NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.9, alpha: 1.0)
    letterColor.setStroke()
    let wPath = NSBezierPath()
    let wX = s * 0.2
    let wY = s * 0.72
    let wWidth = s * 0.18
    let wHeight = s * 0.15
    wPath.move(to: CGPoint(x: wX, y: wY + wHeight))
    wPath.line(to: CGPoint(x: wX + wWidth * 0.25, y: wY))
    wPath.line(to: CGPoint(x: wX + wWidth * 0.5, y: wY + wHeight * 0.6))
    wPath.line(to: CGPoint(x: wX + wWidth * 0.75, y: wY))
    wPath.line(to: CGPoint(x: wX + wWidth, y: wY + wHeight))
    wPath.lineWidth = s * 0.035
    wPath.lineCapStyle = .round
    wPath.lineJoinStyle = .round
    wPath.stroke()

    // Add subtle highlight arc at top
    let highlightColor = NSColor(white: 1.0, alpha: 0.08)
    highlightColor.setFill()
    let highlightPath = NSBezierPath()
    highlightPath.move(to: CGPoint(x: cornerRadius, y: s))
    highlightPath.appendArc(withCenter: CGPoint(x: cornerRadius, y: s - cornerRadius), radius: cornerRadius, startAngle: 90, endAngle: 180)
    highlightPath.line(to: CGPoint(x: 0, y: s * 0.6))
    highlightPath.curve(to: CGPoint(x: s - cornerRadius, y: s), controlPoint1: CGPoint(x: 0, y: s * 0.9), controlPoint2: CGPoint(x: s * 0.5, y: s))
    highlightPath.appendArc(withCenter: CGPoint(x: s - cornerRadius, y: s - cornerRadius), radius: cornerRadius, startAngle: 90, endAngle: 0, clockwise: true)
    highlightPath.close()
    highlightPath.fill()

    image.unlockFocus()
    return image
}

func saveIcon(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path)")
    } catch {
        print("Failed to save \(path): \(error)")
    }
}

// Generate all required sizes
let basePath = "/Users/joshsallows/Library/Mobile Documents/com~apple~CloudDocs/Apps/Josh Well Control for Mac/Josh Well Control for Mac/Assets.xcassets/AppIcon.appiconset"

// Sizes are HALVED because NSImage on Retina doubles them when saving
let sizes: [(size: CGFloat, filename: String)] = [
    // macOS
    (8, "icon_16x16.png"),
    (16, "icon_16x16@2x.png"),
    (16, "icon_32x32.png"),
    (32, "icon_32x32@2x.png"),
    (64, "icon_128x128.png"),
    (128, "icon_128x128@2x.png"),
    (128, "icon_256x256.png"),
    (256, "icon_256x256@2x.png"),
    (256, "icon_512x512.png"),
    (512, "icon_512x512@2x.png"),
    // iOS
    (60, "icon_60x60@2x.png"),
    (90, "icon_60x60@3x.png"),
    (76, "icon_76x76@2x.png"),
    (83.5, "icon_83.5x83.5@2x.png"),  // 83.5 * 2 = 167
    (512, "icon_1024x1024.png"),
]

print("Generating Well Control app icons...")

for (size, filename) in sizes {
    let icon = createAppIcon(size: size)
    let path = "\(basePath)/\(filename)"
    saveIcon(icon, to: path)
}

print("Done! Icons generated at: \(basePath)")
