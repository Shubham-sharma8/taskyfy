#!/usr/bin/env swift
import AppKit
import CoreGraphics

let path = "00-dmg-background.png"
guard let origData = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let origRep = NSBitmapImageRep(data: origData),
      let origCG = origRep.cgImage else {
    fputs("Failed to read 00-dmg-background.png\n", stderr)
    exit(1)
}

let w = 1200
let h = 800

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: w,
          height: h,
          bitsPerComponent: 8,
          bytesPerRow: w * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    exit(1)
}

// 1. Draw original image (preserves exact background #F5F5F5 and center arrow)
ctx.draw(origCG, in: CGRect(x: 0, y: 0, width: w, height: h))

// 2. Clear bottom caption zone (in CoreGraphics bottom-up coords: y = 0..240 corresponds to top-down Y = 560..800)
let bgColor = NSColor(srgbRed: 245.0/255.0, green: 245.0/255.0, blue: 245.0/255.0, alpha: 1.0)
ctx.setFillColor(bgColor.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: w, height: 240))

let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

let pillColor = NSColor(srgbRed: 231.0/255.0, green: 231.0/255.0, blue: 228.0/255.0, alpha: 1.0)
let darkTextColor = NSColor(srgbRed: 15.0/255.0, green: 15.0/255.0, blue: 15.0/255.0, alpha: 1.0)
let line1Gray = NSColor(srgbRed: 102.0/255.0, green: 102.0/255.0, blue: 102.0/255.0, alpha: 1.0)
let line2Gray = NSColor(srgbRed: 117.0/255.0, green: 117.0/255.0, blue: 117.0/255.0, alpha: 1.0)

// Helper to draw a line of [prefix] [pill] [suffix] centered horizontally
func drawLine(
    prefix: String,
    pill: String,
    suffix: String,
    fontSize: CGFloat,
    outerWeight: NSFont.Weight,
    pillWeight: NSFont.Weight,
    outerColor: NSColor,
    centerYBottomUp: CGFloat,
    pillPadX: CGFloat,
    pillHeight: CGFloat,
    pillRadius: CGFloat,
    gap: CGFloat
) {
    let outerFont = NSFont.systemFont(ofSize: fontSize, weight: outerWeight)
    let pillFont = NSFont.systemFont(ofSize: fontSize, weight: pillWeight)

    let outerAttrs: [NSAttributedString.Key: Any] = [
        .font: outerFont,
        .foregroundColor: outerColor,
        .kern: -0.3
    ]
    let pillAttrs: [NSAttributedString.Key: Any] = [
        .font: pillFont,
        .foregroundColor: darkTextColor,
        .kern: -0.3
    ]

    let prefixStr = NSAttributedString(string: prefix, attributes: outerAttrs)
    let pillStr = NSAttributedString(string: pill, attributes: pillAttrs)
    let suffixStr = NSAttributedString(string: suffix, attributes: outerAttrs)

    let prefixSize = prefixStr.size()
    let pillTextSize = pillStr.size()
    let suffixSize = suffixStr.size()

    let pillBoxWidth = ceil(pillTextSize.width) + pillPadX * 2.0
    let totalWidth = prefixSize.width + gap + pillBoxWidth + gap + suffixSize.width
    let startX = round((CGFloat(w) - totalWidth) / 2.0)

    let textBaselineOffset = (outerFont.ascender + outerFont.descender) / 2.0
    let textDrawY = round(centerYBottomUp - prefixSize.height / 2.0)

    // Draw prefix
    prefixStr.draw(at: NSPoint(x: startX, y: textDrawY))

    // Draw pill background
    let pillX = startX + prefixSize.width + gap
    let pillY = round(centerYBottomUp - pillHeight / 2.0)
    let pillRect = NSRect(x: pillX, y: pillY, width: pillBoxWidth, height: pillHeight)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRadius, yRadius: pillRadius)
    pillColor.setFill()
    pillPath.fill()

    // Draw pill text
    let pillTextX = round(pillX + (pillBoxWidth - pillTextSize.width) / 2.0)
    let pillTextY = round(centerYBottomUp - pillTextSize.height / 2.0)
    pillStr.draw(at: NSPoint(x: pillTextX, y: pillTextY))

    // Draw suffix
    let suffixX = pillX + pillBoxWidth + gap
    suffixStr.draw(at: NSPoint(x: suffixX, y: textDrawY))
    _ = textBaselineOffset
}

// Top-down Y=602..653 -> center is 627.5 from top -> 800 - 627.5 = 172.5 from bottom
drawLine(
    prefix: "drag",
    pill: "taskyfy",
    suffix: "into applications, then open it.",
    fontSize: 31.0,
    outerWeight: .medium,
    pillWeight: .bold,
    outerColor: line1Gray,
    centerYBottomUp: 172.5,
    pillPadX: 18.0,
    pillHeight: 52.0,
    pillRadius: 12.0,
    gap: 14.0
)

// Top-down Y=678..715 -> center is 696.5 from top -> 800 - 696.5 = 103.5 from bottom
drawLine(
    prefix: "every metric on your mac.",
    pill: "clear",
    suffix: "in a second.",
    fontSize: 22.0,
    outerWeight: .regular,
    pillWeight: .semibold,
    outerColor: line2Gray,
    centerYBottomUp: 103.5,
    pillPadX: 14.0,
    pillHeight: 38.0,
    pillRadius: 9.0,
    gap: 11.0
)

NSGraphicsContext.restoreGraphicsState()

guard let outCG = ctx.makeImage() else { exit(1) }
let outRep = NSBitmapImageRep(cgImage: outCG)
// Set 144 DPI (600x400 pt)
outRep.size = NSSize(width: 600, height: 400)
guard let pngData = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try pngData.write(to: URL(fileURLWithPath: path))
print("Updated 00-dmg-background.png (1200x800 px @ 144 DPI)")
