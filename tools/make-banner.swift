// Draws the README's animated banner: a MacBook writing "hello" (as in GlassLink for Android),
// next to the GlassLink name. Writes assets/banner-dark.gif and assets/banner-light.gif, on
// backgrounds matching GitHub's dark and light themes so the banner seems to float.
//
//   swift tools/make-banner.swift        (then optimised with gifsicle, if installed)
import AppKit
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let width = 1280, height = 320 // drawn at 2×; shown at 640 × 160
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + top, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: top)
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: bottom)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bottom)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: top)
    p.closeSubpath()
    return p
}

func fill(_ ctx: CGContext, _ path: CGPath, gradient colors: [CGColor], from: CGFloat, to: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - "hello", the same stroke as GlassLink for Android (100 × 44 box)

let helloStart = CGPoint(x: 2, y: 34)
let helloCurves: [[CGFloat]] = [
    [7, 31, 15, 17, 16, 9], [17, 3, 11, 2, 10.5, 9], [10, 17, 9, 29, 8.5, 36],
    [10, 28, 15, 22, 18.5, 22.5], [22, 23, 21.5, 31, 22.5, 35], [23.5, 38, 27.5, 37.5, 30, 33],
    [33, 29, 38, 26.5, 37.5, 23.5], [37, 20.5, 31.5, 21, 31.5, 27], [31.5, 33, 35, 37.5, 40, 36],
    [45, 34, 49, 20, 49.5, 11], [50, 4, 45, 3.5, 44.5, 10], [44, 19, 43.5, 30, 45, 35], [46, 38, 50, 37.5, 53, 33],
    [56, 27, 60, 18, 60.5, 11], [61, 4, 56, 3.5, 55.5, 10], [55, 19, 54.5, 30, 56, 35], [57, 38, 61, 37.5, 64, 32],
    [65.5, 26, 70, 22, 74, 22.5], [79, 23, 80.5, 33, 75.5, 36.5], [71, 39, 66.5, 34, 68, 28.5],
    [69.5, 24, 75, 22, 79, 24], [83, 26, 89, 24, 95, 20],
]

/// The stroke as a dense polyline, so any fraction of it can be drawn.
let helloPoints: [CGPoint] = {
    var points = [helloStart]
    var p0 = helloStart
    for c in helloCurves {
        let p1 = CGPoint(x: c[0], y: c[1]), p2 = CGPoint(x: c[2], y: c[3]), p3 = CGPoint(x: c[4], y: c[5])
        for i in 1...40 {
            let t = CGFloat(i) / 40, u = 1 - t
            points.append(CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                                  y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y))
        }
        p0 = p3
    }
    return points
}()

func helloPath(fraction: CGFloat) -> CGPath {
    var lengths: [CGFloat] = [0]
    for i in 1..<helloPoints.count {
        lengths.append(lengths[i - 1] + hypot(helloPoints[i].x - helloPoints[i - 1].x, helloPoints[i].y - helloPoints[i - 1].y))
    }
    let target = lengths.last! * fraction
    let path = CGMutablePath()
    path.move(to: helloPoints[0])
    for i in 1..<helloPoints.count where lengths[i] <= target { path.addLine(to: helloPoints[i]) }
    return path
}

// MARK: - The MacBook, front view (as in GlassLink for Android)

func drawMacBook(_ ctx: CGContext, in frame: CGRect, write: CGFloat, fade: CGFloat) {
    let w = frame.width
    let lidW = w * 0.84, lidX = frame.minX + (w - lidW) / 2, top = frame.minY
    let lidH = lidW * 0.655, edge = lidW * 0.011
    let aluminium = [color(0xE4E5E8), color(0xBFC1C6)]

    // Contact shadow.
    ctx.saveGState()
    let shadowCenter = CGPoint(x: frame.midX, y: top + lidH * 1.1)
    let shadow = CGGradient(colorsSpace: space, colors: [color(0x000000, 0.45), color(0x000000, 0)] as CFArray, locations: nil)!
    ctx.translateBy(x: shadowCenter.x, y: shadowCenter.y)
    ctx.scaleBy(x: 1, y: 0.08)
    ctx.drawRadialGradient(shadow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w * 0.55, options: [])
    ctx.restoreGState()

    // Lid: aluminium edge, black glass.
    fill(ctx, roundedRect(CGRect(x: lidX, y: top, width: lidW, height: lidH), top: lidW * 0.04, bottom: lidW * 0.008),
         gradient: aluminium, from: top, to: top + lidH)
    ctx.addPath(roundedRect(CGRect(x: lidX + edge, y: top + edge, width: lidW - edge * 2, height: lidH - edge * 1.4),
                            top: lidW * 0.04 - edge, bottom: lidW * 0.008))
    ctx.setFillColor(color(0x070708))
    ctx.fillPath()

    // Display.
    let display = CGRect(x: lidX + lidW * 0.032, y: top + lidW * 0.03, width: lidW * 0.936, height: lidH - lidW * 0.075)
    fill(ctx, roundedRect(display, top: lidW * 0.018, bottom: lidW * 0.004), gradient: [color(0x0B0B0C), color(0x000000)],
         from: display.minY, to: display.maxY)

    // "hello", white to silver, with a soft glow.
    if write > 0, fade > 0 {
        let scale = display.width * 0.6 / 93
        ctx.saveGState()
        ctx.clip(to: display)
        ctx.translateBy(x: display.midX - 48.5 * scale, y: display.midY - 20.5 * scale)
        ctx.scaleBy(x: scale, y: scale)
        let path = helloPath(fraction: write)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (lineWidth, alpha) in [(10.0, 0.025), (7.5, 0.04), (5.5, 0.06)] {
            ctx.addPath(path)
            ctx.setLineWidth(lineWidth)
            ctx.setStrokeColor(color(0xFFFFFF, alpha * fade))
            ctx.strokePath()
        }
        ctx.addPath(path)
        ctx.setLineWidth(3.4)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.setAlpha(fade)
        let g = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xB4B4B4), color(0xFFFFFF)] as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), options: [])
        ctx.restoreGState()
    }

    // Camera notch.
    let notchW = lidW * 0.105, notchH = display.height * 0.055
    ctx.addPath(roundedRect(CGRect(x: frame.midX - notchW / 2, y: display.minY - 1, width: notchW, height: notchH + 1), top: 0, bottom: notchH * 0.45))
    ctx.setFillColor(color(0x070708))
    ctx.fillPath()

    // Hinge, then the base with its thumb scoop.
    let hingeH = lidH * 0.022
    ctx.setFillColor(color(0x2A2B2F))
    ctx.fill(CGRect(x: lidX + lidW * 0.03, y: top + lidH, width: lidW * 0.94, height: hingeH))
    let baseTop = top + lidH + hingeH, baseH = lidH * 0.075
    let base = CGMutablePath()
    base.addRoundedRect(in: CGRect(x: frame.minX, y: baseTop, width: w, height: baseH), cornerWidth: w * 0.03, cornerHeight: baseH * 0.5)
    fill(ctx, base, gradient: [color(0xE4E5E8), color(0xBFC1C6), color(0x8C8F95)], from: baseTop, to: baseTop + baseH)
    ctx.setFillColor(color(0xFFFFFF, 0.8))
    ctx.fill(CGRect(x: frame.minX + w * 0.01, y: baseTop, width: w * 0.98, height: 1))
    let scoopW = w * 0.15
    fill(ctx, roundedRect(CGRect(x: frame.midX - scoopW / 2, y: baseTop, width: scoopW, height: baseH * 0.42), top: 0, bottom: baseH * 0.4),
         gradient: [color(0x8C8F95), color(0xBFC1C6)], from: baseTop, to: baseTop + baseH * 0.42)
}

// MARK: - Frames

struct Theme {
    let name: String
    let background: CGColor
    let ink: NSColor
}

func frame(theme: Theme, write: CGFloat, fade: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(theme.background)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Text, drawn in AppKit's bottom-up coordinates.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let x: CGFloat = 520
    NSAttributedString(string: "GlassLink", attributes: [
        .font: NSFont.systemFont(ofSize: 104, weight: .bold), .foregroundColor: theme.ink, .kern: -2,
    ]).draw(at: NSPoint(x: x - 6, y: 150))
    NSAttributedString(string: "Your Android phone, on your Mac.", attributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .regular), .foregroundColor: theme.ink.withAlphaComponent(0.7),
    ]).draw(at: NSPoint(x: x, y: 96))
    NSAttributedString(string: "macOS  ·  Android  ·  open source", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: theme.ink.withAlphaComponent(0.45), .kern: 1.2,
    ]).draw(at: NSPoint(x: x + 2, y: 50))
    NSGraphicsContext.restoreGraphicsState()

    // The MacBook, in top-down coordinates.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    drawMacBook(ctx, in: CGRect(x: 40, y: 38, width: 420, height: 240), write: write, fade: fade)
    ctx.restoreGState()
    return ctx.makeImage()!
}

func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

/// Write (2.4 s), hold (2 s), fade (0.6 s), pause (0.5 s); then it loops.
func writeGIF(_ theme: Theme, to url: URL) throws {
    var frames: [(CGImage, Double)] = []
    let fps = 20.0
    let writeFrames = Int(2.4 * fps)
    for i in 0...writeFrames { frames.append((frame(theme: theme, write: ease(CGFloat(i) / CGFloat(writeFrames)), fade: 1), 1 / fps)) }
    frames[frames.count - 1].1 = 2.0
    let fadeFrames = Int(0.6 * fps)
    for i in 1...fadeFrames { frames.append((frame(theme: theme, write: 1, fade: 1 - CGFloat(i) / CGFloat(fadeFrames)), 1 / fps)) }
    frames[frames.count - 1].1 = 0.5

    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (image, delay) in frames {
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
        ]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

let assets = repo.appendingPathComponent("assets")
let themes = [
    Theme(name: "dark", background: color(0x0D1117), ink: .white),  // GitHub dark
    Theme(name: "light", background: color(0xFFFFFF), ink: .black), // GitHub light
]
for theme in themes {
    let url = assets.appendingPathComponent("banner-\(theme.name).gif")
    try writeGIF(theme, to: url)
    // Optimise: store only what changes between frames.
    let gifsicle = ["/opt/homebrew/bin/gifsicle", "/usr/local/bin/gifsicle"].first { FileManager.default.fileExists(atPath: $0) }
    if let gifsicle {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gifsicle)
        p.arguments = ["-O3", "--batch", url.path]
        try p.run()
        p.waitUntilExit()
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("Wrote assets/banner-\(theme.name).gif (\(size / 1024) KB)")
}
