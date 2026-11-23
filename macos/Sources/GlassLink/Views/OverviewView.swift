import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    var device: PhoneDevice
    @Binding var section: Section

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                HStack(alignment: .top, spacing: 18) {
                    recentNotifications
                    recentMessages
                }
            }
            .padding(26)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { HeroBackdrop(connected: device.isConnected) }
        .navigationTitle(device.name)
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .help("Look for the phone on the network again")
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 34) {
            PhoneIllustration(device: device, width: 138)
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    HStack(spacing: 7) {
                        ConnectionDot(connected: device.isConnected)
                        Text(statusLine)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }

                HStack(spacing: 22) {
                    BatteryGauge(battery: device.battery)
                    ForEach(device.signals) { signal in
                        HStack(spacing: 6) {
                            SignalBars(strength: signal.strength)
                            Text(signal.networkType).font(.callout.weight(.medium))
                        }
                    }
                }

                QuickActions(device: device)
                ScreenshotStatusLine(device: device)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var statusLine: String {
        if device.isConnected {
            return "Connected over Wi-Fi" + (device.remoteHost.map { " · \($0)" } ?? "")
        }
        if let seen = device.lastSeen { return "Last seen \(seen.formatted(.relative(presentation: .named)))" }
        return "Open KDE Connect on your phone to connect"
    }

    // MARK: Cards

    private var recentNotifications: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Notifications", action: ("Show All", { section = .notifications }))
                if device.notifications.isEmpty {
                    EmptyCardText(device.isConnected ? "Nothing new on your phone." : "Not connected.")
                } else {
                    ForEach(device.notifications.prefix(4)) { notification in
                        HStack(alignment: .top, spacing: 10) {
                            AppIcon(image: notification.iconHash.flatMap { device.icons[$0] }, appName: notification.appName, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notification.title.isEmpty ? notification.appName : notification.title)
                                    .font(.callout.weight(.semibold)).lineLimit(1)
                                Text(notification.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            Text(notification.time.shortRelative).font(.caption).foregroundStyle(.tertiary)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.glass, value: device.notifications.map(\.id))
        }
    }

    private var recentMessages: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Messages", action: ("Open", { section = .messages }))
                if device.conversations.isEmpty {
                    EmptyCardText(device.isConnected ? "Allow SMS access in KDE Connect on your phone to see messages." : "Not connected.")
                } else {
                    ForEach(device.conversations.prefix(4)) { conversation in
                        HStack(spacing: 10) {
                            Avatar(name: device.title(for: conversation), size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.title(for: conversation)).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(conversation.latest.body).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(conversation.latest.date.shortRelative).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

struct EmptyCardText: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

/// The big round buttons under the device name. They share one glass container so they
/// blend into each other as the window resizes.
struct QuickActions: View {
    var device: PhoneDevice
    @State private var rang = 0
    @State private var sentClipboard = 0
    @State private var clipboardNote: String?

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                action("Ring", symbol: "bell.and.waves.left.and.right", trigger: rang) {
                    device.ring()
                    rang += 1
                }
                action("Send Files", symbol: "square.and.arrow.up", trigger: 0) {
                    FilePicker.sendFiles(to: device)
                }
                action(clipboardNote ?? "Clipboard", symbol: clipboardNote == nil ? "doc.on.clipboard" : "checkmark",
                       trigger: sentClipboard) {
                    let result = device.sendClipboard()
                    sentClipboard += 1
                    note(result == .nothing ? "Empty" : "Sent")
                }
                .contextMenu {
                    Button("Send Mac Clipboard to Phone") { _ = device.sendClipboard() }
                    if device.supportsClipboardRequest {
                        Button("Get Phone's Clipboard") {
                            device.requestPhoneClipboard()
                            note("Asked")
                        }
                    }
                }
                action("Ping", symbol: "hand.wave", trigger: 0) { device.ping() }
            }
        }
        .disabled(!device.isReady)
    }

    private func note(_ text: String) {
        withAnimation(.glass) { clipboardNote = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.glass) { clipboardNote = nil }
        }
    }

    private func action(_ title: String, symbol: String, trigger: Int, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce, value: trigger)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                Text(title).font(.caption.weight(.medium))
                    .contentTransition(.opacity)
            }
            .frame(width: 74)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .help(title)
    }
}

/// A soft wash of the accent color behind the hero, fading out as you scroll.
struct HeroBackdrop: View {
    var connected: Bool

    var body: some View {
        LinearGradient(
            colors: [Color.primary.opacity(connected ? 0.06 : 0.03), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 420)
        .ignoresSafeArea()
        .animation(.glass, value: connected)
    }
}


/// One line under the quick actions: whether phone screenshots are syncing.
struct ScreenshotStatusLine: View {
    var device: PhoneDevice

    var body: some View {
        if let (symbol, text, tint) = content {
            Label {
                Text(text).lineLimit(2)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
            .animation(.glass, value: device.screenshotStatus)
        }
    }

    private var content: (String, String, Color)? {
        guard device.isReady else { return nil }
        switch device.screenshotStatus {
        case .off: return nil
        case .connecting: return ("camera.viewfinder", "Connecting to the phone's screenshots…", .secondary)
        case .watching: return ("camera.viewfinder", "Screenshots on the phone are copied to this Mac instantly", .primary)
        case .pushed: return ("bolt.fill", "Screenshots and copied images sync instantly (GlassLink for Android)", .primary)
        case .needsPermission: return ("exclamationmark.lock", "Allow “All files access” for KDE Connect on the phone to sync screenshots", .secondary)
        case .failed(let reason): return ("exclamationmark.triangle", "Screenshot sync: \(reason)", .secondary)
        }
    }
}
