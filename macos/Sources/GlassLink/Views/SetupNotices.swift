import SwiftUI

/// Shown on the Overview when something stops phone notifications or calls from reaching the Mac:
/// macOS banners turned off for GlassLink, or permissions still missing on the phone.
struct SetupNotices: View {
    @Environment(AppModel.self) private var model
    var device: PhoneDevice
    @State private var askedPhone = false

    private var phoneNeeds: [String] { device.isReady ? device.setupMissing : [] }

    var body: some View {
        if model.notificationPermission != .allowed || !phoneNeeds.isEmpty {
            VStack(spacing: 12) {
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
                Button(button, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}
