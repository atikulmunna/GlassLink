// Draws the README's animated banner: a MacBook writing "hello" (as in GlassLink for Android), a
// handshake, and an Android phone on which the Android robot assembles itself. No text. Writes
// assets/greeting-dark.gif and assets/greeting-light.gif, on backgrounds matching GitHub's dark and
// light themes so the banner seems to float.
//
// The Android robot is reproduced or modified from work created and shared by Google and used
// according to terms described in the Creative Commons 3.0 Attribution License. The handshake is
// Material Symbols "handshake" (Apache License 2.0), in tools/handshake.svg.
//
//   swift tools/make-banner.swift        (then optimised with gifsicle, if installed)
import AppKit
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let width = 960, height = 320 // drawn at 2×; shown at 480 × 160
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

// MARK: - Motion

func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
/// 0 → 1 with a little overshoot, like a spring.
func spring(_ t: CGFloat) -> CGFloat {
    let p = clamp(t)
    return p >= 1 ? 1 : 1 - cos(p * .pi * 2.2) * exp(-p * 5.5)
}
/// Progress of a step that runs from `start` for `duration` seconds.
func step(_ time: CGFloat, _ start: CGFloat, _ duration: CGFloat) -> CGFloat { clamp((time - start) / duration) }

// MARK: - The Android phone and the robot

/// An Android phone, front view: aluminium frame, black glass, punch-hole camera, side keys.
func drawPhone(_ ctx: CGContext, in r: CGRect, content: (CGRect) -> Void) {
    // Contact shadow.
    ctx.saveGState()
    let shadow = CGGradient(colorsSpace: space, colors: [color(0x000000, 0.4), color(0x000000, 0)] as CFArray, locations: nil)!
    ctx.translateBy(x: r.midX, y: r.maxY + 4)
    ctx.scaleBy(x: 1, y: 0.12)
    ctx.drawRadialGradient(shadow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r.width * 0.75, options: [])
    ctx.restoreGState()

    // Side keys, then the frame and the glass.
    ctx.setFillColor(color(0xA6A9AF))
    ctx.fill(CGRect(x: r.maxX - 1, y: r.minY + r.height * 0.22, width: 3, height: r.height * 0.1))
    ctx.fill(CGRect(x: r.maxX - 1, y: r.minY + r.height * 0.36, width: 3, height: r.height * 0.06))
    let body = CGPath(roundedRect: r, cornerWidth: r.width * 0.17, cornerHeight: r.width * 0.17, transform: nil)
    fill(ctx, body, gradient: [color(0xE4E5E8), color(0xA9ACB2)], from: r.minY, to: r.maxY)
    let glass = r.insetBy(dx: 3, dy: 3)
    ctx.addPath(CGPath(roundedRect: glass, cornerWidth: r.width * 0.15, cornerHeight: r.width * 0.15, transform: nil))
    ctx.setFillColor(color(0x070708))
    ctx.fillPath()
    let screen = glass.insetBy(dx: 4, dy: 4)
    fill(ctx, CGPath(roundedRect: screen, cornerWidth: r.width * 0.12, cornerHeight: r.width * 0.12, transform: nil),
         gradient: [color(0x0B0B0C), color(0x000000)], from: screen.minY, to: screen.maxY)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: r.width * 0.12, cornerHeight: r.width * 0.12, transform: nil))
    ctx.clip()
    content(screen)
    ctx.restoreGState()
    // Punch-hole camera.
    ctx.setFillColor(color(0x1C2433))
    ctx.fillEllipse(in: CGRect(x: r.midX - 4, y: screen.minY + 9, width: 8, height: 8))
}

/// The Android robot (in a 100 × 112 box) assembling itself between `time` 0 and about 2.3 s:
/// body rises, legs drop in, head pops on, arms swing in, antennae grow, eyes open and blink.
func drawRobot(_ ctx: CGContext, in screen: CGRect, time t: CGFloat, fade: CGFloat) {
    guard fade > 0, t > 0 else { return }
    let scale = screen.width * 0.62 / 100
    ctx.saveGState()
    ctx.translateBy(x: screen.midX - 50 * scale, y: screen.midY - 56 * scale + 4)
    ctx.scaleBy(x: scale, y: scale)

    let white = [color(0xFFFFFF), color(0xB9B9B9), color(0xFFFFFF)]
    func paint(_ path: CGPath, alpha: CGFloat) {
        guard alpha > 0 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha * fade)
        for (width, glow) in [(9.0, 0.03), (6.0, 0.05)] { // soft glow, as on the "hello"
            ctx.addPath(path)
            ctx.setLineWidth(width)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(color(0xFFFFFF, glow))
            ctx.strokePath()
        }
        ctx.addPath(path)
        ctx.clip()
        let g = CGGradient(colorsSpace: space, colors: white as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 112), options: [])
        ctx.restoreGState()
    }
    func capsule(_ r: CGRect) -> CGPath { CGPath(roundedRect: r, cornerWidth: r.width / 2, cornerHeight: r.width / 2, transform: nil) }

    // Body: grows up from its base.
    let body = step(t, 0.0, 0.55)
    if body > 0 {
        let h = 50 * spring(body)
        let path = CGMutablePath()
        let rect = CGRect(x: 18, y: 94 - h, width: 64, height: h)
        path.addPath(roundedRectBottom(rect, radius: min(10, h / 2)))
        paint(path, alpha: clamp(body * 3))
    }
    // Legs: drop in from below.
    let legs = step(t, 0.3, 0.5)
    let legOffset = (1 - spring(legs)) * 18
    paint(capsule(CGRect(x: 33, y: 84 + legOffset, width: 11, height: 28)), alpha: clamp(legs * 3))
    paint(capsule(CGRect(x: 56, y: 84 + legOffset, width: 11, height: 28)), alpha: clamp(legs * 3))
    // Head: pops on, with a little overshoot.
    let head = step(t, 0.55, 0.55)
    if head > 0 {
        ctx.saveGState()
        let k = spring(head)
        ctx.translateBy(x: 50, y: 40)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -50, y: -40)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 50, y: 40), radius: 32, startAngle: .pi, endAngle: 0, clockwise: false)
        path.closeSubpath()
        paint(path, alpha: clamp(head * 3))
        ctx.restoreGState()
    }
    // Arms: swing in from the sides.
    let arms = step(t, 0.8, 0.55)
    let armOffset = (1 - spring(arms)) * 14
    paint(capsule(CGRect(x: 4 - armOffset, y: 46, width: 11, height: 36)), alpha: clamp(arms * 3))
    paint(capsule(CGRect(x: 85 + armOffset, y: 46, width: 11, height: 36)), alpha: clamp(arms * 3))
    // Antennae: grow outward from the head.
    let antennae = ease(step(t, 1.15, 0.4))
    if antennae > 0 {
        ctx.saveGState()
        ctx.setAlpha(fade)
        ctx.setLineCap(.round)
        ctx.setLineWidth(3.6)
        ctx.setStrokeColor(color(0xEDEDED))
        for (from, to) in [(CGPoint(x: 37, y: 15), CGPoint(x: 29, y: 3)), (CGPoint(x: 63, y: 15), CGPoint(x: 71, y: 3))] {
            ctx.move(to: from)
            ctx.addLine(to: CGPoint(x: from.x + (to.x - from.x) * antennae, y: from.y + (to.y - from.y) * antennae))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
    // Eyes: open, then blink once.
    let eyes = step(t, 1.45, 0.25)
    if eyes > 0, head >= 1 {
        let blink = step(t, 2.6, 0.18)
        let openness = eyes * (blink > 0 && blink < 1 ? abs(1 - 2 * blink) : 1)
        ctx.setFillColor(color(0x000000, fade))
        for x in [38.0, 62.0] {
            ctx.fillEllipse(in: CGRect(x: x - 3.8, y: 28 - 3.8 * openness, width: 7.6, height: 7.6 * max(openness, 0.08)))
        }
    }
    ctx.restoreGState()
}

/// A rectangle with square top corners and rounded bottom ones (the robot's body).
func roundedRectBottom(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
    p.closeSubpath()
    return p
}

// MARK: - The handshake (Material Symbols, tools/handshake.svg)

func handshakeImage(ink: String) -> NSImage {
    var svg = try! String(contentsOf: repo.appendingPathComponent("tools/handshake.svg"), encoding: .utf8)
    svg = svg.replacingOccurrences(of: "<path d=", with: "<path fill=\"\(ink)\" d=")
    return NSImage(data: Data(svg.utf8))!
}

// MARK: - Frames

struct Theme {
    let name: String
    let background: CGColor
    let handshake: NSImage
}

func frame(theme: Theme, time t: CGFloat, fade: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(theme.background)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height)) // top-down from here on
    ctx.scaleBy(x: 1, y: -1)

    // Layout: MacBook 400, gap, handshake 92, gap, phone 128; centred.
    let macWidth: CGFloat = 400, gap: CGFloat = 46, shake: CGFloat = 92, phoneSize = CGSize(width: 128, height: 268)
    let left = (CGFloat(width) - (macWidth + gap + shake + gap + phoneSize.width)) / 2
    drawMacBook(ctx, in: CGRect(x: left, y: 40, width: macWidth, height: 240), write: ease(step(t, 0, 2.4)), fade: fade)

    // Handshake: pops in partway through, pulses once both greetings are done.
    let pop = spring(step(t, 1.0, 0.6))
    let pulse = step(t, 2.75, 0.35)
    let k = pop * (1 + 0.12 * sin(pulse * .pi))
    if pop > 0 {
        let center = CGPoint(x: left + macWidth + gap + shake / 2, y: 150)
        let size = shake * k
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        theme.handshake.draw(in: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                             from: .zero, operation: .sourceOver, fraction: clamp(step(t, 1.0, 0.25)) * fade, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    let phone = CGRect(x: left + macWidth + gap + shake + gap, y: 24, width: phoneSize.width, height: phoneSize.height)
    drawPhone(ctx, in: phone) { screen in drawRobot(ctx, in: screen, time: t - 0.4, fade: fade) }
    return ctx.makeImage()!
}

/// Both greetings (about 3 s), hold (1.6 s), fade (0.6 s), pause (0.4 s); then it loops.
func writeGIF(_ theme: Theme, to url: URL) throws {
    var frames: [(CGImage, Double)] = []
    let fps = 20.0
    let active = Int(3.1 * fps)
    for i in 0...active { frames.append((frame(theme: theme, time: CGFloat(i) / CGFloat(fps), fade: 1), 1 / fps)) }
    frames[frames.count - 1].1 = 1.6
    let fadeFrames = Int(0.6 * fps)
    for i in 1...fadeFrames {
        frames.append((frame(theme: theme, time: 3.1, fade: 1 - CGFloat(i) / CGFloat(fadeFrames)), 1 / fps))
    }
    frames[frames.count - 1].1 = 0.4

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
    Theme(name: "dark", background: color(0x0D1117), handshake: handshakeImage(ink: "#E6E6E6")),  // GitHub dark
    Theme(name: "light", background: color(0xFFFFFF), handshake: handshakeImage(ink: "#1A1A1A")), // GitHub light
]
for theme in themes {
    let url = assets.appendingPathComponent("greeting-\(theme.name).gif")
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
    print("Wrote assets/greeting-\(theme.name).gif (\(size / 1024) KB)")
}
