#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Uses the Canva minimal black-and-white logo mark (Design ID: DAHafeKpN-M)
let canvaLogoPath = "Marketing/screenshots/canva-taskyfy-logo.png"
let canvaSourceImage = NSImage(contentsOfFile: canvaLogoPath)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84)
    let radius = s * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 1. Pure White Minimal Squircle Background (#FFFFFF)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.fill(rect)

    if let src = canvaSourceImage {
        // Draw the upper geometric symbol mark from the Canva design (cropping out the bottom wordmark so the macOS icon is a pure symbol mark)
        let srcSize = src.size
        let cropRect = NSRect(
            x: srcSize.width * 0.18,
            y: srcSize.height * 0.41,
            width: srcSize.width * 0.64,
            height: srcSize.height * 0.46
        )
        let targetRect = NSRect(
            x: s * 0.18,
            y: s * 0.21,
            width: s * 0.64,
            height: s * 0.58
        )
        src.draw(in: targetRect, from: cropRect, operation: .sourceOver, fraction: 1.0)
    }

    ctx.restoreGState()

    // 2. Subtle crisp black squircle border
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.14))
    ctx.setLineWidth(max(1.0, s * 0.018))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    let img = renderIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    let fileURL = URL(fileURLWithPath: outDir).appendingPathComponent(filename)
    try png.write(to: fileURL)
}
print("Generated iconset at \(outDir)")
