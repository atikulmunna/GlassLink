import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    var device: PhoneDevice
    @Binding var section: Section

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                SetupNotices(device: device)
                HStack(alignment: .top, spacing: 18) {
                    recentNotifications
                    recentMessages
                }
            }
            .padding(26)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .animation(.glass, value: device.setupMissing)
        .animation(.glass, value: model.notificationPermission)
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
        return "Open \(device.phoneAppName) on your phone to connect"
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
                    EmptyCardText(device.isConnected ? "Allow SMS access in \(device.phoneAppName) on your phone to see messages." : "Not connected.")
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

/// The round Liquid Glass buttons under the device name. They share one glass container, spring
/// on hover, bounce when tapped, and pop in one after another when the screen appears.
struct QuickActions: View {
    var device: PhoneDevice
    @Environment(\.openWindow) private var openWindow
    @State private var rang = 0
    @State private var sentFiles = 0
    @State private var sentClipboard = 0
    @State private var pinged = 0
    @State private var clipboardNote: String?
    @State private var appeared = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 20) {
                GlassActionButton(title: "Ring", symbol: "bell.and.waves.left.and.right", trigger: rang, index: 0, appeared: appeared) {
                    device.ring()
                    rang += 1
                }
                GlassActionButton(title: "Send Files", symbol: "square.and.arrow.up", trigger: sentFiles, index: 1, appeared: appeared) {
                    sentFiles += 1
                    FilePicker.sendFiles(to: device)
                }
                GlassActionButton(title: clipboardNote ?? "Clipboard", symbol: clipboardNote == nil ? "doc.on.clipboard" : "checkmark",
                                  trigger: sentClipboard, index: 2, appeared: appeared) {
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
                GlassActionButton(title: "Ping", symbol: "hand.wave", trigger: pinged, index: 3, appeared: appeared) {
                    device.ping()
                    pinged += 1
                }
                if device.supportsMirroring {
                    GlassActionButton(title: "Mirror", symbol: "rectangle.on.rectangle", trigger: 0, index: 4, appeared: appeared) {
                        openWindow(id: "mirror")
                    }
                }
            }
        }
        .disabled(!device.isReady)
        .onAppear { appeared = true }
    }

    private func note(_ text: String) {
        withAnimation(.glass) { clipboardNote = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.glass) { clipboardNote = nil }
        }
    }
}

/// One round glass button with its label underneath.
struct GlassActionButton: View {
    var title: String
    var symbol: String
    var trigger: Int
    var index = 0
    var appeared = true
    var size: CGFloat = 52
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .symbolEffect(.bounce.up, value: trigger)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(hovering ? 1.08 : 1)
            .onHover { over in hovering = over && isEnabled }
            .animation(.spring(duration: 0.35, bounce: 0.45), value: hovering)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(minWidth: size + 18)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.6)
        .animation(.spring(duration: 0.5, bounce: 0.35).delay(Double(index) * 0.06), value: appeared)
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
        case .needsPermission: return ("exclamationmark.lock", "Allow “All files access” for \(device.phoneAppName) on the phone to sync screenshots", .secondary)
        case .failed(let reason): return ("exclamationmark.triangle", "Screenshot sync: \(reason)", .secondary)
        }
    }
}
