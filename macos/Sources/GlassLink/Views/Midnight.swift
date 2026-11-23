import AppKit
import SwiftUI

/// GlassLink's look on both platforms: midnight and white. Pure black (or white, in light mode),
/// white (or black) type and controls, greyscale everything else. The Android app uses the same
/// palette (GlassLinkPalette.kt).
enum Midnight {
    /// Black in dark mode, white in light mode.
    static let background = Color(nsColor: NSColor(name: "GlassLinkBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })

    /// Greys for avatars and placeholders, from light to dark.
    static let greys: [Color] = [0.62, 0.54, 0.46, 0.38, 0.30].map { Color(white: $0) }
}

extension View {
    /// Monochrome controls on a black (or white) window.
    func midnightWindow() -> some View {
        tint(.primary)
            .containerBackground(Midnight.background, for: .window)
    }
}
