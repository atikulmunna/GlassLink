// Draws the README's comparison table, with the GlassLink column as a solid band (black in light
// mode, white in dark mode), to assets/comparison-light.svg and assets/comparison-dark.svg.
// GitHub's Markdown can't color table cells, so the table is an image; the rows live here.
//
//     swift tools/make-comparison.swift

import AppKit

enum Cell {
    case yes
    case no
    case text(String)
}

let columns = ["Phone Link", "KDE Connect on Mac", "GlassLink"]

let rows: [(String, [Cell])] = [
    ("Runs on a Mac", [.text("Windows only"), .text("Experimental (Qt)"), .text("Native SwiftUI")]),
    ("Mirror the phone's screen", [.text("Select phones"), .no, .text("Any phone")]),
    ("Use it with mouse and keyboard", [.text("Select phones"), .no, .yes]),
    ("Notifications with reply", [.yes, .yes, .yes]),
    ("Text messages (SMS)", [.yes, .text("Partial"), .yes]),
    ("Incoming call alerts", [.yes, .yes, .yes]),
    ("Answer or decline calls", [.yes, .no, .yes]),
    ("Talk through the computer", [.yes, .no, .no]),
    ("Text copy and paste", [.yes, .yes, .yes]),
    ("Image copy and paste", [.text("Select phones"), .no, .text("Both ways")]),
    ("Phone screenshots on the computer", [.yes, .text("Manual"), .text("Instant")]),
    ("Send files", [.yes, .yes, .text("Drag and drop")]),
    ("No account or cloud needed", [.text("Microsoft account"), .yes, .yes]),
    ("Open source", [.no, .yes, .yes]),
]

struct Theme {
    let name: String
    let text: String
    let muted: String
    let line: String
    let band: String
    let bandText: String
    let bandLine: String
    let bandMuted: String
}

// GitHub's own light and dark text and border colors, so the table sits naturally on the page.
let themes = [
    Theme(name: "light", text: "#1f2328", muted: "#59636e", line: "#d1d9e0",
          band: "#000000", bandText: "#ffffff", bandLine: "#ffffff29", bandMuted: "#ffffff80"),
    Theme(name: "dark", text: "#f0f6fc", muted: "#9198a1", line: "#3d444d",
          band: "#ffffff", bandText: "#000000", bandLine: "#0000001f", bandMuted: "#00000073"),
]

// Layout (pixels at 1x).
let width = 900
let labelX = 24
let columnEdges = [320, 500, 680, 892] // left edges of the three columns, then the right edge
let headerHeight = 94
let rowHeight = 46
let height = headerHeight + rows.count * rowHeight + 14
let band = (x: 686, y: 6, width: 200, height: height - 12, radius: 20)
let font = "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif"

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

/// The app icon, small, as a data URL (so the SVG stays a single file).
func iconDataURL() -> String {
    let source = NSImage(contentsOf: repo.appendingPathComponent("assets/icon.png"))!
    let pixels = 64
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return "data:image/png;base64," + rep.representation(using: .png, properties: [:])!.base64EncodedString()
}

func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
}

func center(_ column: Int) -> Int { (columnEdges[column] + columnEdges[column + 1]) / 2 }

func svg(_ t: Theme, icon: String) -> String {
    var out: [String] = []
    out.append("""
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" \
    font-family="\(font)" role="img">
    <title>Phone Link, KDE Connect on Mac and GlassLink compared</title>
    <rect x="\(band.x)" y="\(band.y)" width="\(band.width)" height="\(band.height)" rx="\(band.radius)" fill="\(t.band)"/>
    """)

    // Header: the GlassLink icon above its name; the other names on the same baseline.
    let baseline = headerHeight - 22
    for (i, name) in columns.enumerated() {
        let isGlassLink = i == columns.count - 1
        if isGlassLink {
            // A soft tile, so the black icon still reads on the black band.
            out.append("""
            <rect x="\(center(i) - 21)" y="11" width="42" height="42" rx="12" fill="\(t.bandLine)"/>
            <image href="\(icon)" x="\(center(i) - 16)" y="16" width="32" height="32"/>
            """)
        }
        out.append("""
        <text x="\(center(i))" y="\(baseline)" text-anchor="middle" font-size="15" font-weight="\(isGlassLink ? 700 : 600)" \
        fill="\(isGlassLink ? t.bandText : t.text)">\(escape(name))</text>
        """)
    }

    for (r, row) in rows.enumerated() {
        let top = headerHeight + r * rowHeight
        let mid = top + rowHeight / 2
        // Row divider: across the label and first two columns, and fainter inside the band.
        out.append("""
        <line x1="16" y1="\(top)" x2="\(columnEdges[2] - 4)" y2="\(top)" stroke="\(t.line)" stroke-width="1"/>
        <line x1="\(band.x + 18)" y1="\(top)" x2="\(band.x + band.width - 18)" y2="\(top)" stroke="\(t.bandLine)" stroke-width="1"/>
        <text x="\(labelX)" y="\(mid + 5)" font-size="15" fill="\(t.text)">\(escape(row.0))</text>
        """)
        for (i, cell) in row.1.enumerated() {
            let isGlassLink = i == columns.count - 1
            let ink = isGlassLink ? t.bandText : t.text
            let muted = isGlassLink ? t.bandMuted : t.muted
            let x = center(i)
            switch cell {
            case .yes:
                out.append("""
                <path d="M\(x - 7) \(mid) l5 5 l10 -10.5" fill="none" stroke="\(ink)" stroke-width="2.4" \
                stroke-linecap="round" stroke-linejoin="round"/>
                """)
            case .no:
                out.append("""
                <line x1="\(x - 6)" y1="\(mid)" x2="\(x + 6)" y2="\(mid)" stroke="\(muted)" stroke-width="2" stroke-linecap="round"/>
                """)
            case .text(let s):
                out.append("""
                <text x="\(x)" y="\(mid + 5)" text-anchor="middle" font-size="14" font-weight="\(isGlassLink ? 600 : 400)" \
                fill="\(isGlassLink ? ink : t.muted)">\(escape(s))</text>
                """)
            }
        }
    }
    out.append("</svg>")
    return out.joined(separator: "\n") + "\n"
}

let icon = iconDataURL()
for theme in themes {
    let url = repo.appendingPathComponent("assets/comparison-\(theme.name).svg")
    try! svg(theme, icon: icon).write(to: url, atomically: true, encoding: .utf8)
    print("Wrote assets/comparison-\(theme.name).svg")
}
