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

/// Settings › Theme: follow macOS, or always light or dark.
@MainActor
enum Theme {
    static func apply(_ choice: String) {
        switch choice {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil // follow macOS
        }
    }
}

extension View {
    /// Monochrome controls on a black (or white) window.
    func midnightWindow() -> some View {
        tint(.primary)
            .containerBackground(Midnight.background, for: .window)
    }
}

/// GlassLink's prominent buttons: a solid capsule in the text color (black in light mode, white in
/// dark mode) with the opposite color for the label, so it always reads. The system's
/// .glassProminent with the window's .primary tint drew black text on a dark button in light mode.
struct MidnightProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 3 : 6)
            .background(Capsule().fill(scheme == .dark ? Color.white : Color.black))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MidnightProminentButtonStyle {
    static var midnightProminent: MidnightProminentButtonStyle { MidnightProminentButtonStyle() }
}
