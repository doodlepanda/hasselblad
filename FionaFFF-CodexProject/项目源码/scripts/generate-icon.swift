#!/usr/bin/env swift
import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/FionaFFF.app/Contents/Resources/AppIcon.icns"
let sourcePath = CommandLine.arguments.dropFirst(2).first ?? "Sources/ImgSlicer/Resources/AppIconSource.png"
let outputURL = URL(fileURLWithPath: outputPath)
let sourceURL = URL(fileURLWithPath: sourcePath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset", isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Cannot load icon source at \(sourceURL.path)")
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
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

for (name, pixels) in sizes {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    let iconRect = NSRect(origin: .zero, size: size)
    let radius = size.width * 0.225
    let clipPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: size.width * 0.035, dy: size.height * 0.035), xRadius: radius, yRadius: radius)
    clipPath.addClip()
    NSColor.black.setFill()
    iconRect.fill()
    let sourceSize = sourceImage.size
    let scale = min(size.width / max(1, sourceSize.width), size.height / max(1, sourceSize.height))
    let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = NSRect(
        x: (size.width - drawSize.width) / 2,
        y: (size.height - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot render \(name)")
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}

try? FileManager.default.removeItem(at: iconsetURL)
