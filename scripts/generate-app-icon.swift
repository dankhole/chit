#!/usr/bin/env swift
// Editable vector artwork. Regenerate on macOS: swift scripts/generate-app-icon.swift
// Uses no fonts, external images, dependencies, or normal app build products.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func gradient(_ context: CGContext, colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Geometry uses a 1024-point, top-left-origin artboard. Transparent margins match
// the visual size of macOS app icons. Small sizes omit decorative surface details.
func drawIcon(in context: CGContext, pixels: Int) {
    context.saveGState()
    defer { context.restoreGState() }
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x11111b, alpha: 0.28))
    context.setFillColor(color(0x1e1e2e))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    gradient(context, colors: [color(0x3a3b50), color(0x1e1e2e)],
             from: CGPoint(x: 220, y: 100), to: CGPoint(x: 720, y: 924))
    context.restoreGState()
    if pixels >= 64 {
        context.addPath(CGPath(roundedRect: CGRect(x: 102, y: 102, width: 820, height: 820),
                               cornerWidth: 184, cornerHeight: 184, transform: nil))
        context.setStrokeColor(color(0xcdd6f4, alpha: 0.12))
        context.setLineWidth(2)
        context.strokePath()
    }

    // A slightly turned paper chit is the whole mark. The dark check preserves
    // contrast, while the folded corner carries Mocha's blue accent.
    context.translateBy(x: 512, y: 512)
    context.rotate(by: -7 * .pi / 180)
    context.translateBy(x: -512, y: -512)
    let paper = CGMutablePath()
    paper.move(to: CGPoint(x: 346, y: 236))
    paper.addLine(to: CGPoint(x: 620, y: 236))
    paper.addLine(to: CGPoint(x: 720, y: 336))
    paper.addLine(to: CGPoint(x: 720, y: 746))
    paper.addQuadCurve(to: CGPoint(x: 678, y: 788), control: CGPoint(x: 720, y: 788))
    paper.addLine(to: CGPoint(x: 346, y: 788))
    paper.addQuadCurve(to: CGPoint(x: 304, y: 746), control: CGPoint(x: 304, y: 788))
    paper.addLine(to: CGPoint(x: 304, y: 278))
    paper.addQuadCurve(to: CGPoint(x: 346, y: 236), control: CGPoint(x: 304, y: 236))
    paper.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -20), blur: 30, color: color(0x11111b, alpha: 0.40))
    context.addPath(paper)
    context.setFillColor(color(0xcdd6f4))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(paper)
    context.clip()
    gradient(context, colors: [color(0xe6eaff), color(0xcdd6f4)],
             from: CGPoint(x: 440, y: 236), to: CGPoint(x: 570, y: 788))
    context.restoreGState()
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 620, y: 236))
    fold.addLine(to: CGPoint(x: 720, y: 336))
    fold.addLine(to: CGPoint(x: 646, y: 336))
    fold.addQuadCurve(to: CGPoint(x: 620, y: 310), control: CGPoint(x: 620, y: 336))
    fold.closeSubpath()
    context.addPath(fold)
    context.setFillColor(color(0x89b4fa))
    context.fillPath()
    context.setStrokeColor(color(0x313244))
    context.setLineWidth(54)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 397, y: 506))
    context.addLine(to: CGPoint(x: 480, y: 589))
    context.addLine(to: CGPoint(x: 635, y: 421))
    context.strokePath()
    // A short rule suggests a note without adding texture at small sizes.
    if pixels >= 32 {
        context.setStrokeColor(color(0x8c9ac0))
        context.setLineWidth(18)
        context.move(to: CGPoint(x: 407, y: 690))
        context.addLine(to: CGPoint(x: 610, y: 690))
        context.strokePath()
    }
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: context, pixels: pixels)
    return context.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

func bigEndian(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}

// Modern macOS ICNS families contain PNG representations in typed chunks. Write
// the container directly so asset regeneration does not depend on iconutil.
// Include both standard and Retina representations, down to 16 points.
let representations: [(String, Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
    ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
]
var chunks = Data()
for (type, size) in representations {
    let data = png(render(pixels: size))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(data.count + 8))
    chunks.append(data)
}
var family = Data("icns".utf8)
family.append(bigEndian(chunks.count + 8))
family.append(chunks)
try family.write(to: resources.appendingPathComponent("Chit.icns"))
try png(render(pixels: 1024)).write(to: resources.appendingPathComponent("ChitIcon.png"))
print("Generated Resources/Chit.icns and Resources/ChitIcon.png")
