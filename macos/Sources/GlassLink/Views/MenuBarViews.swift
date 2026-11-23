import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let device = model.current, device.isConnected {
            HStack(spacing: 3) {
                Image(systemName: device.call != nil ? "phone.fill" : "smartphone")
                if let battery = device.battery { Text("\(battery.level)%").monospacedDigit() }
            }
        } else {
            Image(systemName: "smartphone.slash")
        }
    }
}

/// The menu bar window: the phone at a glance, quick actions, latest notifications.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let device = model.current {
                header(device)
                if let call = device.call {
                    HStack {
                        Image(systemName: "phone.fill").foregroundStyle(.primary)
                        Text(call.name).font(.callout.weight(.semibold))
                        Spacer()
                        if call.kind == .ringing {
                            Button("Silence") { device.muteRinger() }.buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        small("Ring", "bell.and.waves.left.and.right") { device.ring() }
                        small("Files", "square.and.arrow.up") { FilePicker.sendFiles(to: device) }
                        small("Clipboard", "doc.on.clipboard") { device.sendClipboard() }
                    }
                }
                .disabled(!device.isReady)

                if !device.notifications.isEmpty {
                    Divider()
                    ForEach(device.notifications.prefix(4)) { notification in
                        HStack(alignment: .top, spacing: 9) {
                            AppIcon(image: notification.iconHash.flatMap { device.icons[$0] }, appName: notification.appName, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notification.title.isEmpty ? notification.appName : notification.title)
                                    .font(.caption.weight(.semibold)).lineLimit(1)
                                Text(notification.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                Text("No phone paired").font(.headline)
                Text("Open GlassLink to pair your Android phone.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open GlassLink") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func header(_ device: PhoneDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName).font(.title2).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                HStack(spacing: 6) {
                    ConnectionDot(connected: device.isConnected)
                    Text(device.isConnected ? "Connected" : "Not connected").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                BatteryGauge(battery: device.battery, compact: true)
                if let signal = device.signals.first {
                    HStack(spacing: 4) {
                        SignalBars(strength: signal.strength, height: 9)
                        Text(signal.networkType).font(.caption2)
                    }
                }
            }
        }
    }

    private func small(_ title: String, _ symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(height: 18)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}
