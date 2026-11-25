import SwiftUI

// MARK: - Motion

extension Animation {
    /// The app's one spring: quick, with a hint of overshoot.
    static let glass = Animation.spring(duration: 0.42, bounce: 0.18)
}

// MARK: - Glass surfaces

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct SectionTitle: View {
    var title: String
    var action: (label: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Battery

struct BatteryGauge: View {
    var battery: BatteryState?
    var compact = false

    private var tint: Color { battery == nil ? .secondary : .primary }

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: compact ? 3 : 4, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.6), lineWidth: 1.2)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: compact ? 1.5 : 2.5, style: .continuous)
                        .fill(tint.opacity(battery == nil ? 0.25 : 0.9))
                        .frame(width: max(2, (geo.size.width - 4) * CGFloat(battery?.level ?? 0) / 100))
                        .padding(2)
                }
                if battery?.isCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: compact ? 7 : 9, weight: .bold))
                        .foregroundStyle(Midnight.background)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: compact ? 22 : 30, height: compact ? 11 : 14)
            .overlay(alignment: .trailing) {
                Capsule().fill(.secondary.opacity(0.6)).frame(width: 2, height: compact ? 4 : 6).offset(x: 3)
            }
            Text(battery.map { "\($0.level)%" } ?? "—")
                .font(compact ? .caption.monospacedDigit() : .callout.monospacedDigit().weight(.medium))
                .contentTransition(.numericText(value: Double(battery?.level ?? 0)))
        }
        .animation(.glass, value: battery)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.map { "Battery \($0.level) percent\($0.isCharging ? ", charging" : "")" } ?? "Battery unknown")
    }
}

// MARK: - Signal

struct SignalBars: View {
    var strength: Int
    var height: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { bar in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(bar < strength ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: height / 4, height: height * CGFloat(bar + 1) / 4)
            }
        }
        .animation(.glass, value: strength)
        .accessibilityLabel("\(strength) of 4 bars")
    }
}

// MARK: - Avatars

struct Avatar: View {
    var name: String
    var size: CGFloat = 36
    var image: NSImage?
    @Environment(\.colorScheme) private var scheme

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first(where: \.isLetter) }
        if letters.isEmpty { return name.first(where: \.isNumber) != nil ? "#" : "?" }
        return String(letters).uppercased()
    }

    private var color: Color {
        let palette = scheme == .dark ? Midnight.greys : Midnight.lightGreys
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [color.opacity(0.95), color.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.72))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A notification's app icon from the phone, or the app's initial.
struct AppIcon: View {
    var image: NSImage?
    var appName: String
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.12)
            } else {
                Text(appName.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Phone illustration

/// A stylised phone, used as the hero image. The screen shows the time and battery.
struct PhoneIllustration: View {
    var device: PhoneDevice
    var width: CGFloat = 150

    /// The phone's own wallpaper when GlassLink for Android has sent it, else its colours, else ours.
    @ViewBuilder private var screen: some View {
        if let wallpaper = device.wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
                .overlay {
                    // Keep the clock legible on bright wallpapers.
                    LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .transition(.opacity)
        } else {
            let colors = device.wallpaperColors.isEmpty
                ? [Color(white: 0.24), Color(white: 0.10), Color(white: 0.04)]
                : device.wallpaperColors.map { Color(nsColor: $0) }
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        let height = width * 2.05
        TimelineView(.everyMinute) { context in
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(.black.gradient)
                screen
                    .clipShape(.rect(cornerRadius: width * 0.15, style: .continuous))
                    .padding(width * 0.035)
                VStack(spacing: 4) {
                    Circle().fill(.black).frame(width: width * 0.06).padding(.top, width * 0.07)
                    Spacer()
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: width * 0.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        .contentTransition(.numericText())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.system(size: width * 0.075, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if let battery = device.battery {
                        Label("\(battery.level)%", systemImage: battery.isCharging ? "bolt.fill" : "battery.75")
                            .font(.system(size: width * 0.07, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.bottom, width * 0.12)
                    }
                }
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            .saturation(device.isConnected ? 1 : 0.35)
            .animation(.glass, value: device.wallpaper)
            .animation(.glass, value: device.isConnected)
        }
    }
}

// MARK: - Status

struct ConnectionDot: View {
    var connected: Bool

    var body: some View {
        Circle()
            .fill(connected ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: 8, height: 8)
            .overlay { if connected { Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3) } }
            .animation(.glass, value: connected)
    }
}

extension Date {
    var shortRelative: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if Calendar.current.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        if seconds < 6 * 86400 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(date: .numeric, time: .omitted)
    }
}
