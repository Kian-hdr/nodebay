#!/usr/bin/env swift

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconURL = projectRoot.appendingPathComponent("Design/NodebayIcon/Nodebay-AppIcon-1024.png")
let outputDirectory = projectRoot.appendingPathComponent("Design/SocialPreview", isDirectory: true)
let outputURL = outputDirectory.appendingPathComponent("Nodebay-GitHub-Social-Preview.png")

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

guard let icon = NSImage(contentsOf: iconURL) else {
    fatalError("Unable to load Nodebay icon at \(iconURL.path)")
}

let width = 1280
let height = 640
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap")
}

bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create graphics context")
}
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.015, green: 0.035, blue: 0.075, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.095, blue: 0.19, alpha: 1),
])!
gradient.draw(in: canvas, angle: 0)

NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
NSBezierPath(roundedRect: NSRect(x: 46, y: 46, width: 1188, height: 548), xRadius: 40, yRadius: 40).fill()

NSColor(calibratedWhite: 0, alpha: 0.72).setFill()
NSBezierPath(roundedRect: NSRect(x: 510, y: 560, width: 260, height: 80), xRadius: 30, yRadius: 30).fill()

icon.draw(
    in: NSRect(x: 116, y: 140, width: 360, height: 360),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .left

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 84, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
let taglineAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.91, alpha: 1),
    .paragraphStyle: paragraph,
]
let detailAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.72, blue: 1, alpha: 1),
    .paragraphStyle: paragraph,
]

NSAttributedString(string: "Nodebay", attributes: titleAttributes).draw(
    in: NSRect(x: 540, y: 350, width: 650, height: 110)
)
NSAttributedString(
    string: "The utility bay in your Mac’s notch.",
    attributes: taglineAttributes
).draw(in: NSRect(x: 544, y: 270, width: 650, height: 88))
NSAttributedString(
    string: "LOCAL-FIRST  •  APPLE SILICON  •  OPEN SOURCE",
    attributes: detailAttributes
).draw(in: NSRect(x: 546, y: 205, width: 650, height: 44))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode preview")
}
try data.write(to: outputURL, options: .atomic)
print(outputURL.path)
