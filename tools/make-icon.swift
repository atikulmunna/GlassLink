// Draws the GlassLink app icon. One drawing serves both apps, so they always match.
// Run from anywhere:   swift tools/make-icon.swift
//
// Writes:
//   macos/Resources/AppIcon.icns     macOS icon (squircle with a soft shadow)
//   android/src/main/res/...         Android adaptive icon (background, foreground, monochrome),
//                                    legacy launcher PNGs, status-bar icon, in-app logo
//   assets/icon.png, assets/banner.png   for the README
//
// Midnight and white, like both apps: a black field, white frosted glass, no colour.
import AppKit

let canvas: CGFloat = 1024

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A rectangle with one radius for the top corners and another for the bottom ones.
func rounded(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + top, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: top)
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: bottom)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bottom)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: top)
    p.closeSubpath()
    return p
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// Renders at `size` pixels into a top-down 1024-point canvas.
func render(size: Int, _ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - The drawing

/// Midnight: near-black at the top fading to black, with one faint white light from above.
func drawBackground(_ ctx: CGContext, in rect: CGRect) {
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x1a1a1a), color(0x000000)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let center = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.2)
    let light = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.09), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width * 0.6, options: [])
}

/// A frosted pane: translucent white, darker toward the bottom, with a bright rim.
func glassPane(_ ctx: CGContext, _ path: CGPath, top: CGFloat, bottom: CGFloat, strength: CGFloat, mono: Bool) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if mono {
        ctx.setFillColor(color(0xffffff, 0.45 * strength))
        ctx.fill(path.boundingBox)
    } else {
        let fill = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.34 * strength), color(0xffffff, 0.10 * strength)] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    }
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(mono ? 9 : 5)
    ctx.setStrokeColor(color(0xffffff, mono ? 1 : 0.6 * strength))
    ctx.strokePath()
    ctx.restoreGState()
}

/// A MacBook, the phone in front of it, and the link between them, in the 1024 canvas.
/// Its bounding box is about x 130–800, y 245–800. `mono` draws a single-colour silhouette.
func drawArtwork(_ ctx: CGContext, mono: Bool = false) {
    // MacBook lid, back left: frosted glass with the camera notch.
    let lid = CGRect(x: 175, y: 245, width: 500, height: 335)
    glassPane(ctx, rounded(lid, top: 40, bottom: 10), top: lid.minY, bottom: lid.maxY, strength: 0.85, mono: mono)
    ctx.addPath(rounded(CGRect(x: lid.midX - 34, y: lid.minY + 4, width: 68, height: 20), top: 0, bottom: 9))
    ctx.setFillColor(color(0xffffff, mono ? 1 : 0.55))
    ctx.fillPath()
    for (rect, alpha) in [(CGRect(x: 222, y: 300, width: 190, height: 26), CGFloat(0.85)),
                          (CGRect(x: 222, y: 344, width: 140, height: 22), CGFloat(0.45)),
                          (CGRect(x: 222, y: 382, width: 168, height: 22), CGFloat(0.45))] {
        ctx.addPath(rounded(rect, rect.height / 2))
        ctx.setFillColor(color(0xffffff, mono ? 1 : alpha))
        ctx.fillPath()
    }
    // Base: a thin aluminium slab, wider than the lid.
    let base = CGRect(x: 130, y: 590, width: 590, height: 26)
    ctx.saveGState()
    ctx.addPath(rounded(base, top: 6, bottom: 13))
    ctx.clip()
    if mono {
        ctx.setFillColor(color(0xffffff, 0.85))
        ctx.fill(base)
    } else {
        let metal = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.9), color(0xffffff, 0.45)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
    }
    ctx.restoreGState()

    // Phone, front right, overlapping the display.
    let phone = CGRect(x: 560, y: 330, width: 240, height: 470)
    ctx.saveGState()
    if mono {
        ctx.addPath(rounded(phone.insetBy(dx: -14, dy: -14), 68)) // gap so the phone reads in front
        ctx.setBlendMode(.clear)
        ctx.fillPath()
    } else {
        ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x000000, 0.45))
        ctx.addPath(rounded(phone, 56))
        ctx.setFillColor(color(0x0a0a0a, 0.6))
        ctx.fillPath()
    }
    ctx.restoreGState()
    if mono {
        ctx.addPath(rounded(phone, 56))
        ctx.setFillColor(color(0xffffff))
        ctx.fillPath()
    } else {
        glassPane(ctx, rounded(phone, 56), top: phone.minY, bottom: phone.maxY, strength: 1, mono: false)
    }

    // Camera dot and a notification bubble on the phone (cut out of the silhouette).
    ctx.saveGState()
    if mono { ctx.setBlendMode(.clear) }
    ctx.addEllipse(in: CGRect(x: 668, y: 356, width: 24, height: 24))
    ctx.setFillColor(color(0x000000, 0.7))
    ctx.fillPath()
    let bubble = CGRect(x: 588, y: 420, width: 184, height: 74)
    ctx.addPath(rounded(bubble, 26))
    ctx.setFillColor(color(0xffffff, 0.85))
    ctx.fillPath()
    ctx.restoreGState()
    if !mono {
        ctx.addEllipse(in: CGRect(x: 602, y: 437, width: 40, height: 40))
        ctx.setFillColor(color(0x111111, 0.85))
        ctx.fillPath()
        for (y, width) in [(CGFloat(442), CGFloat(100)), (CGFloat(464), CGFloat(70))] {
            ctx.addPath(rounded(CGRect(x: 654, y: y, width: width, height: 13), 6.5))
            ctx.setFillColor(color(0x1a1a1a, 0.55))
            ctx.fillPath()
        }
    }

    // The link: two arcs flowing from the phone to the display.
    ctx.setLineCap(.round)
    for (radius, alpha) in [(CGFloat(62), CGFloat(0.9)), (CGFloat(112), CGFloat(0.55))] {
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 572, y: 700), radius: radius, startAngle: .pi * 0.84, endAngle: .pi * 1.16, clockwise: false)
        ctx.addPath(arc)
        ctx.setLineWidth(18)
        ctx.setStrokeColor(color(0xffffff, mono ? 1 : alpha))
        ctx.strokePath()
    }
}

/// Centers the artwork on the canvas at `scale`. Its bounds are x 130–800 (base to phone),
/// y 245–800 (lid to phone), so its center is (465, 522.5).
func centered(_ ctx: CGContext, scale: CGFloat, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: canvas / 2, y: canvas / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -465, y: -522.5)
    draw()
    ctx.restoreGState()
}

// MARK: - macOS

func macIcon(size: Int) -> Data {
    render(size: size) { ctx in
        // Body on Apple's icon grid, with a soft shadow.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let bodyPath = rounded(body, 186)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x000000, 0.35))
        ctx.addPath(bodyPath)
        ctx.setFillColor(color(0x000000))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        drawBackground(ctx, in: body)
        centered(ctx, scale: 0.9) { drawArtwork(ctx) } // ~73% of the body, centred
        ctx.restoreGState()
    }
}

/// The repository root (this script lives in tools/).
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func writeMacIcon(preview: URL?) throws {
    let fm = FileManager.default
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GlassLink.iconset")
    try? fm.removeItem(at: iconset)
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try macIcon(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        try macIcon(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
    let output = repo.appendingPathComponent("macos/Resources/AppIcon.icns")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    if let preview { try macIcon(size: 512).write(to: preview) }
    print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
}

// MARK: - Android

/// Adaptive icon layers are 108dp; launchers mask them to the inner ~72dp and keep the inner
/// 66dp circle always visible, so the artwork is drawn at 0.66× to sit inside it.
func writeAndroidIcon(res: URL, preview: URL?) throws {
    let fm = FileManager.default
    let layers = res.appendingPathComponent("drawable-nodpi")
    try fm.createDirectory(at: layers, withIntermediateDirectories: true)
    let layerSize = 432 // 108dp at xxxhdpi
    try render(size: layerSize) { drawBackground($0, in: CGRect(x: 0, y: 0, width: canvas, height: canvas)) }
        .write(to: layers.appendingPathComponent("glasslink_icon_background.png"))
    try render(size: layerSize) { ctx in centered(ctx, scale: 0.66) { drawArtwork(ctx) } }
        .write(to: layers.appendingPathComponent("glasslink_icon_foreground.png"))
    try render(size: layerSize) { ctx in centered(ctx, scale: 0.66) { drawArtwork(ctx, mono: true) } }
        .write(to: layers.appendingPathComponent("glasslink_icon_monochrome.png"))

    // Legacy launcher icons (Android 7 and older): the same, pre-masked.
    func legacy(size: Int, round: Bool) -> Data {
        render(size: size) { ctx in
            let field = CGRect(x: 32, y: 32, width: canvas - 64, height: canvas - 64)
            ctx.addPath(round ? CGPath(ellipseIn: field, transform: nil) : rounded(field, 200))
            ctx.clip()
            drawBackground(ctx, in: field)
            centered(ctx, scale: 0.78) { drawArtwork(ctx) }
        }
    }
    for (folder, size) in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)] {
        let dir = res.appendingPathComponent(folder)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try legacy(size: size, round: false).write(to: dir.appendingPathComponent("ic_launcher.png"))
        try legacy(size: size, round: true).write(to: dir.appendingPathComponent("ic_launcher_round.png"))
    }
    // Status-bar notification icon: the white silhouette, padded to Android's 24dp grid.
    for (folder, size) in [("drawable-mdpi", 24), ("drawable-hdpi", 36), ("drawable-xhdpi", 48), ("drawable-xxhdpi", 72), ("drawable-xxxhdpi", 96)] {
        let dir = res.appendingPathComponent(folder)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try render(size: size) { ctx in centered(ctx, scale: 1.45) { drawArtwork(ctx, mono: true) } }
            .write(to: dir.appendingPathComponent("ic_notification.png"))
    }
    // The in-app logo (about screen, notifications' large icon).
    for (folder, size) in [("drawable-mdpi", 48), ("drawable-hdpi", 72), ("drawable-xhdpi", 96), ("drawable-xxhdpi", 144)] {
        try legacy(size: size, round: false).write(to: res.appendingPathComponent(folder).appendingPathComponent("icon.png"))
    }
    if let preview {
        // Background + foreground through a circular mask, as a launcher would show it.
        try render(size: 512) { ctx in
            ctx.addEllipse(in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
            ctx.clip()
            drawBackground(ctx, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
            centered(ctx, scale: 0.66 * 108 / 72) { drawArtwork(ctx) }
        }.write(to: preview)
    }
    print("Wrote Android icons to \(res.path)")
}

// MARK: - README artwork

/// A wide midnight banner: the icon, the name, and one line about what GlassLink is.
func writeBanner(to url: URL) throws {
    let width = 1600, height = 520
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(color(0x000000))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let light = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.07), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: 420, y: 420), startRadius: 0, endCenter: CGPoint(x: 420, y: 420), endRadius: 700, options: [])

    // The icon, drawn at 340 px.
    let icon = NSImage(data: macIcon(size: 680))!
    icon.draw(in: NSRect(x: 150, y: 90, width: 340, height: 340))

    // Name and tagline (SF Pro, white and grey).
    let name = NSAttributedString(string: "GlassLink", attributes: [
        .font: NSFont.systemFont(ofSize: 128, weight: .bold), .foregroundColor: NSColor.white, .kern: -2.5,
    ])
    name.draw(at: NSPoint(x: 560, y: 250))
    let tagline = NSAttributedString(string: "Your Android phone, on your Mac.", attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .regular), .foregroundColor: NSColor(white: 0.72, alpha: 1),
    ])
    tagline.draw(at: NSPoint(x: 566, y: 178))
    let platforms = NSAttributedString(string: "macOS  ·  Android  ·  open source", attributes: [
        .font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: NSColor(white: 0.45, alpha: 1), .kern: 1.5,
    ])
    platforms.draw(at: NSPoint(x: 568, y: 118))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Main

let assets = repo.appendingPathComponent("assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try writeMacIcon(preview: assets.appendingPathComponent("icon.png"))
try writeAndroidIcon(res: repo.appendingPathComponent("android/src/main/res"), preview: nil)
try writeBanner(to: assets.appendingPathComponent("banner.png"))
print("Wrote assets/icon.png and assets/banner.png")
