import SwiftUI

/// Shown on the Overview when something stops phone notifications or calls from reaching the Mac:
/// macOS banners turned off for GlassLink, or permissions still missing on the phone.
struct SetupNotices: View {
    @Environment(AppModel.self) private var model
    var device: PhoneDevice
    @State private var askedPhone = false

    private var phoneNeeds: [String] { device.isReady ? device.setupMissing : [] }

    private var updateShown: Bool {
        switch model.updater.state {
        case .available, .downloading, .installing: true
        default: false
        }
    }

    var body: some View {
        if model.notificationPermission != .allowed || !phoneNeeds.isEmpty || updateShown {
            VStack(spacing: 12) {
                if updateShown { UpdateNotice(updater: model.updater) }
                if model.notificationPermission != .allowed {
                    notice(symbol: "bell.slash",
                           title: "Notifications are off for GlassLink",
                           detail: "Phone notifications and calls only show inside this window until you allow banners.",
                           button: model.notificationPermission == .notAsked ? "Allow" : "Open Settings") {
                        model.notifier.fixPermission()
                    }
                }
                if !phoneNeeds.isEmpty {
                    notice(symbol: "iphone.gen3.badge.exclamationmark",
                           title: "Finish setting up on \(device.name)",
                           detail: "Waiting for permission on the phone: \(ListFormatter.localizedString(byJoining: phoneNeeds)). "
                               + "If Android says a setting is restricted, open App info for GlassLink, tap ⋮ and choose Allow restricted settings.",
                           button: askedPhone ? "Check Your Phone" : "Show on Phone") {
                        device.requestSetupStatus(show: true)
                        askedPhone = true
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func notice(symbol: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(button, action: action).buttonStyle(.midnightProminent)
            }
        }
    }
}

/// "GlassLink 0.2.3 is available", with Install, then progress while it downloads and installs.
private struct UpdateNotice: View {
    var updater: Updater

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                switch updater.state {
                case .available(let release):
                    Link("What's New", destination: release.page).font(.callout)
                    Button("Install") { Task { await updater.install() } }.buttonStyle(.midnightProminent)
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 110)
                default:
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var title: String {
        switch updater.state {
        case .available(let release): "GlassLink \(release.version) is available"
        case .downloading: "Downloading the update…"
        default: "Installing the update…"
        }
    }

    private var detail: String {
        switch updater.state {
        case .available: "You have \(Updater.currentVersion). It installs and reopens in a few seconds."
        case .downloading(let fraction): "\(Int(fraction * 100))%"
        default: "GlassLink quits and reopens by itself."
        }
    }
}
