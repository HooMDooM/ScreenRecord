#!/usr/bin/env swift
// Draws the app icon set (dark rounded square with a green record ring)
// into the .iconset directory passed as the first argument.
import AppKit

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let inset = side * 0.06
    let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = body.width * 0.225

    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.24, green: 0.22, blue: 0.27, alpha: 1),
                                       CGColor(red: 0.13, green: 0.12, blue: 0.15, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    context.saveGState()
    context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    context.restoreGState()

    let ringRect = CGRect(x: side * 0.26, y: side * 0.26, width: side * 0.48, height: side * 0.48)
    context.setStrokeColor(CGColor(red: 0.271, green: 0.855, blue: 0.541, alpha: 1))
    context.setLineWidth(side * 0.055)
    context.strokeEllipse(in: ringRect)

    let dot = ringRect.insetBy(dx: ringRect.width * 0.26, dy: ringRect.height * 0.26)
    context.setFillColor(CGColor(red: 0.925, green: 0.286, blue: 0.239, alpha: 1))
    context.fillEllipse(in: dot)

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    guard let data = drawIcon(size: variant.size) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(variant.name).png"))
}
