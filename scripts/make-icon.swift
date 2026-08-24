#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns.
//
// The mark: two overlapping speech bubbles on an indigo→cyan squircle — a light
// one holding a Latin "A", a dark one holding the Persian "ف". Two scripts, two
// bubbles: reads as "translation between these two languages" at any size, and
// stays legible down to 16pt because the shapes are big and the contrast between
// the two bubbles is light-vs-dark rather than hue-vs-hue.
//
// Run:  swift scripts/make-icon.swift
//

import AppKit

let S: CGFloat = 1024  // master canvas

// MARK: - Palette

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1)
}

let gradientTop = rgb(0x6366F1)  // indigo
let gradientBottom = rgb(0x0EA5E9)  // sky
let inkDark = rgb(0x1E1B4B)  // near-black indigo, for the dark bubble
let bubbleLight = rgb(0xFFFFFF)

// MARK: - Shapes

/// Rounded-rect speech bubble with a tail on the given bottom corner.
func bubblePath(_ rect: CGRect, radius: CGFloat, tailOnLeft: Bool) -> CGPath {
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let path = CGMutablePath()
    path.addPath(body)

    // Tail: a soft triangle hanging off the bottom edge, inset from the corner
    // so it never collides with the rounded corner itself.
    let tail = CGMutablePath()
    let inset: CGFloat = radius * 0.9
    let width: CGFloat = 78
    let drop: CGFloat = 74
    if tailOnLeft {
        let x = rect.minX + inset
        tail.move(to: CGPoint(x: x, y: rect.minY + 6))
        tail.addLine(to: CGPoint(x: x - 18, y: rect.minY - drop))
        tail.addLine(to: CGPoint(x: x + width, y: rect.minY + 6))
    } else {
        let x = rect.maxX - inset
        tail.move(to: CGPoint(x: x, y: rect.minY + 6))
        tail.addLine(to: CGPoint(x: x + 18, y: rect.minY - drop))
        tail.addLine(to: CGPoint(x: x - width, y: rect.minY + 6))
    }
    tail.closeSubpath()
    path.addPath(tail)
    return path
}

/// Expands a bubble outline outward, used to knock a clean gap into whatever
/// sits beneath the front bubble so the two never visually merge.
func outlinePath(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func drawGlyph(_ text: String, in rect: CGRect, color: CGColor, size: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color)!,
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let bounds = attributed.boundingRect(
        with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    let origin = CGPoint(
        x: rect.midX - bounds.width / 2 - bounds.minX,
        y: rect.midY - bounds.height / 2 - bounds.minY)
    attributed.draw(at: origin)
}

// MARK: - Render

let image = NSImage(size: CGSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Squircle plate. Inset leaves the margin macOS expects around app icons.
let plate = CGRect(x: 88, y: 88, width: S - 176, height: S - 176)
let platePath = CGPath(
    roundedRect: plate, cornerWidth: 196, cornerHeight: 196, transform: nil)

func fillPlateGradient(clipTo path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [gradientTop, gradientBottom] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: [])
    ctx.restoreGState()
}

fillPlateGradient(clipTo: platePath)

// Soft highlight across the top so the plate doesn't read as flat vinyl.
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let sheen = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(
    sheen,
    startCenter: CGPoint(x: plate.midX, y: plate.maxY), startRadius: 0,
    endCenter: CGPoint(x: plate.midX, y: plate.maxY), endRadius: plate.width * 0.85,
    options: [])
ctx.restoreGState()

// Bubbles. Light one sits back-left, dark one front-right.
let backRect = CGRect(x: 168, y: 496, width: 392, height: 326)
let frontRect = CGRect(x: 466, y: 214, width: 392, height: 326)
let backPath = bubblePath(backRect, radius: 92, tailOnLeft: true)
let frontPath = bubblePath(frontRect, radius: 92, tailOnLeft: false)

func withShadow(_ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10), blur: 26,
        color: CGColor(red: 0.05, green: 0.05, blue: 0.2, alpha: 0.28))
    body()
    ctx.restoreGState()
}

withShadow {
    ctx.addPath(backPath)
    ctx.setFillColor(bubbleLight)
    ctx.fillPath()
}

// Knock a gradient-coloured gap where the front bubble overlaps the back one,
// by repainting the plate gradient through the front bubble's expanded outline.
fillPlateGradient(clipTo: outlinePath(frontPath, width: 34))

withShadow {
    ctx.addPath(frontPath)
    ctx.setFillColor(inkDark)
    ctx.fillPath()
}

drawGlyph("A", in: backRect, color: inkDark, size: 210)
drawGlyph("ف", in: frontRect, color: bubbleLight, size: 230)

image.unlockFocus()

// MARK: - Write iconset + icns

let root = URL(fileURLWithPath: CommandLine.arguments.first!)
    .deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("build.noindex/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func write(_ pixels: Int, _ name: String) {
    let target = NSImage(size: CGSize(width: pixels, height: pixels))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: CGRect(x: 0, y: 0, width: pixels, height: pixels),
        from: CGRect(x: 0, y: 0, width: S, height: S),
        operation: .copy, fraction: 1)
    target.unlockFocus()

    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { fatalError("failed to encode \(name)") }
    try! png.write(to: iconset.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    write(size, "icon_\(size)x\(size).png")
    write(size * 2, "icon_\(size)x\(size)@2x.png")
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }

// Keep a full-size preview around; handy for README and for eyeballing changes.
let previewURL = root.appendingPathComponent("build.noindex/AppIcon-preview.png")
if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: previewURL)
}

print("Wrote \(icns.path)")
print("Preview: \(previewURL.path)")
