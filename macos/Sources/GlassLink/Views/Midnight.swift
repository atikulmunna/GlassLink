import AppKit
import SwiftUI

/// GlassLink's look. Dark mode: midnight and white (pure black, white type and controls,
/// greyscale everything else; the Android app's GlassLinkPalette.kt matches). Light mode is
/// colourful: the macOS accent colour on controls, pastel contact circles, a green battery.
enum Midnight {
    /// Black in dark mode, white in light mode.
    static let background = Color(nsColor: NSColor(name: "GlassLinkBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })

    /// Greys for avatars and placeholders in dark mode (with white initials), from light to dark.
    static let greys: [Color] = [0.62, 0.54, 0.46, 0.38, 0.30].map { Color(white: $0) }
    /// Light mode: soft pastel circles, with initials in a darker shade of the same hue.
    static let pastels: [(fill: Color, ink: Color)] = [
        (Color(red: 0.89, green: 0.85, blue: 0.98), Color(red: 0.40, green: 0.25, blue: 0.72)), // violet
        (Color(red: 0.84, green: 0.95, blue: 0.87), Color(red: 0.12, green: 0.50, blue: 0.26)), // green
        (Color(red: 1.00, green: 0.90, blue: 0.80), Color(red: 0.72, green: 0.38, blue: 0.06)), // orange
        (Color(red: 0.84, green: 0.91, blue: 1.00), Color(red: 0.15, green: 0.38, blue: 0.78)), // blue
        (Color(red: 0.99, green: 0.86, blue: 0.91), Color(red: 0.72, green: 0.18, blue: 0.40)), // pink
        (Color(red: 0.82, green: 0.94, blue: 0.94), Color(red: 0.08, green: 0.47, blue: 0.50)), // teal
    ]

    /// The same name always gets the same pastel.
    static func pastel(for name: String) -> (fill: Color, ink: Color) {
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return pastels[abs(hash) % pastels.count]
    }
}

/// Settings › Theme: follow macOS, or always light or dark.
@MainActor
enum Theme {
    /// Whether macOS itself is in Dark mode right now. In System mode NSApp.appearance is nil, so the
    /// app's effective appearance is macOS's. (A UserDefaults suite for the global domain isn't
    /// allowed and always read nil, which made System look light.)
    static var systemIsDark: Bool {
        if NSApp.appearance == nil {
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func apply(_ choice: String) {
        switch choice {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil // follow macOS
        }
    }
}

/// Applies Settings › Theme through SwiftUI, so every view repaints when it changes (setting
/// NSApp.appearance alone only updated the AppKit parts, like the sidebar). "System" follows macOS
/// live. GLASSLINK_APPEARANCE=light or dark overrides it, for checking a look.
struct ThemedWindow: ViewModifier {
    @AppStorage("theme") private var theme = "system"
    @State private var systemDark = Theme.systemIsDark

    private var scheme: ColorScheme {
        switch ProcessInfo.processInfo.environment["GLASSLINK_APPEARANCE"] ?? theme {
        case "light": .light
        case "dark": .dark
        default: systemDark ? .dark : .light
        }
    }

    func body(content: Content) -> some View {
        content
            // Midnight controls in dark mode; the macOS accent colour in light mode.
            .tint(scheme == .dark ? Color.primary : Color.accentColor)
            .preferredColorScheme(scheme)
            .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in systemDark = Theme.systemIsDark }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
                systemDark = Theme.systemIsDark
            }
            .onChange(of: theme) { _, _ in systemDark = Theme.systemIsDark }
    }
}

extension View {
    /// Monochrome controls on a black (or white) window, in the chosen theme.
    func midnightWindow() -> some View {
        containerBackground(Midnight.background, for: .window)
            .modifier(ThemedWindow())
    }

    /// The theme alone, for the menu bar panel and Settings.
    func midnightTheme() -> some View {
        modifier(ThemedWindow())
    }
}

/// GlassLink's prominent buttons: white with black text in dark mode, the accent colour with white
/// text in light mode, so the label always reads. (The system's .glassProminent with a .primary
/// tint drew black text on a dark button in light mode.)
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
            .background(Capsule().fill(scheme == .dark ? Color.white : Color.accentColor))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MidnightProminentButtonStyle {
    static var midnightProminent: MidnightProminentButtonStyle { MidnightProminentButtonStyle() }
}
