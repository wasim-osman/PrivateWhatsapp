import AppKit
import CoreGraphics

let size = 1024

let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let greenLight = CGColor(srgbRed: 0.145, green: 0.827, blue: 0.400, alpha: 1)
let greenDark = CGColor(srgbRed: 0.070, green: 0.549, blue: 0.494, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

let fullRect = CGRect(x: 0, y: 0, width: size, height: size)

ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

let bgPath = CGPath(roundedRect: fullRect, cornerWidth: 229, cornerHeight: 229, transform: nil)
let gradient = CGGradient(colorsSpace: sRGB, colors: [greenLight, greenDark] as CFArray, locations: [0, 1])!

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])
ctx.restoreGState()

let bubble = CGMutablePath()
bubble.addRoundedRect(in: CGRect(x: 160, y: 190, width: 704, height: 644), cornerWidth: 150, cornerHeight: 150)
bubble.move(to: CGPoint(x: 300, y: 210))
bubble.addLine(to: CGPoint(x: 140, y: 60))
bubble.addLine(to: CGPoint(x: 480, y: 165))
bubble.closeSubpath()
ctx.addPath(bubble)
ctx.setFillColor(white)
ctx.fillPath()

let symbol = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)!
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 480, weight: .bold))!

let glyphCtx = CGContext(
    data: nil,
    width: 620,
    height: 620,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: glyphCtx, flipped: true)
symbol.draw(in: CGRect(x: 0, y: 0, width: 620, height: 620))
NSGraphicsContext.restoreGraphicsState()
let glyph = glyphCtx.makeImage()!

ctx.saveGState()
ctx.clip(to: CGRect(x: 202, y: 202, width: 620, height: 620), mask: glyph)
ctx.setFillColor(greenDark)
ctx.fill(CGRect(x: 202, y: 202, width: 620, height: 620))
ctx.restoreGState()

let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
