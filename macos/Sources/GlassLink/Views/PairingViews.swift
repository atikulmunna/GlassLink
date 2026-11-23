import SwiftUI

/// First run: explains the phone side, lists nearby phones and pairs with one.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var manualHost = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.primary)
                        .symbolEffect(.breathe, options: .repeating)
                    Text("Link Your Android Phone")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Notifications, messages, calls, files and your clipboard — on your Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 30)

                HStack(alignment: .top, spacing: 16) {
                    Step(number: 1, title: "Install KDE Connect", detail: "Get it from Google Play or F-Droid on your phone. It's free and open source.")
                    Step(number: 2, title: "Same Wi-Fi", detail: "Keep the phone and this Mac on the same network.")
                    Step(number: 3, title: "Pair", detail: "Pick your phone below, or tap “\(model.localName)” in the app on your phone.")
                }
                .frame(maxWidth: 760)

                nearby
                    .frame(maxWidth: 520)

                statusFooter
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { HeroBackdrop(connected: true) }
    }

    private var nearby: some View {
        GlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Nearby Phones").font(.headline)
                    Spacer()
                    if model.nearbyDevices.isEmpty { ProgressView().controlSize(.small) }
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
                if model.nearbyDevices.isEmpty {
                    Text("Looking for phones running KDE Connect…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    ForEach(model.nearbyDevices) { device in
                        NearbyRow(device: device)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("Phone not showing up? Enter its IP address", text: $manualHost)
                        .textFieldStyle(.plain)
                        .onSubmit(addHost)
                    Button("Connect", action: addHost)
                        .buttonStyle(.glass)
                        .disabled(manualHost.isEmpty)
                }
                .font(.callout)
            }
            .animation(.glass, value: model.nearbyDevices.map(\.id))
        }
    }

    private var statusFooter: some View {
        Group {
            switch model.status {
            case .starting:
                Text("Starting…")
            case .running:
                Text("This Mac appears as “\(model.localName)” on your phone.")
            case .failed(let reason):
                Label("Couldn't start networking: \(reason)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.primary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func addHost() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        var hosts = Prefs.customHosts
        if !hosts.contains(host) { hosts.append(host) }
        UserDefaults.standard.set(hosts.joined(separator: ","), forKey: "customHosts")
        manualHost = ""
        model.refresh()
    }
}

private struct Step: View {
    var number: Int
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded))
                .frame(width: 28, height: 28)
                .glassEffect(.regular, in: .circle)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct NearbyRow: View {
    var device: PhoneDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbolName)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.semibold))
                if case .requested = device.pairState, let code = device.pairingCode {
                    Text("Accept on your phone. Code: \(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if let host = device.remoteHost {
                    Text(host).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch device.pairState {
            case .requested:
                ProgressView().controlSize(.small)
                Button("Cancel") { device.rejectPairing() }
                    .buttonStyle(.glass)
            case .requestedByPeer:
                Button("Respond") { AppModel.shared.pairingRequest = device }
                    .buttonStyle(.glassProminent)
            default:
                Button("Pair") { withAnimation(.glass) { device.requestPairing() } }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shown when a phone asks to pair. Both screens show the same code.
struct PairRequestSheet: View {
    var device: PhoneDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: device.symbolName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.primary)
                .padding(.top, 6)
            Text("Pair with \(device.name)?").font(.title2.weight(.semibold))
            Text("It will be able to show notifications, send files and use your clipboard. Check the code matches the one on the phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let code = device.pairingCode {
                Text(code)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .kerning(4)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Button("Decline", role: .cancel) {
                    device.rejectPairing()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
                Button("Pair") {
                    device.acceptPairing()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 400)
        .onChange(of: device.pairState) { _, state in
            if !state.isPending { dismiss() }
        }
    }
}
